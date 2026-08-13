--!strict
-- Native-sheet model specs (native-stylesheets stage, ledger NSS-A1/NSS-A9/
-- NSS-I1): the PURE model builder is fully assertable headlessly — token
-- values equal the Luau styles, names are human-readable, rule order encodes
-- the measured cascade (insertion order wins), every $token reference
-- resolves in every theme, mirrors are complete, and every theme re-passes
-- the contrast gate. Paint application itself is E3 (Studio scenario).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")

local function build()
	return sheet_model.build({
		themes = {
			{ name = "Dark", style = default_style },
			{ name = "Light", style = light_style },
		},
	})
end

local function ruleIndex(model: any, name: string): number
	for i, r in model.rules do
		if r.name == name then
			return i
		end
	end
	error(`rule '{name}' not found`)
end

describe("sheet_model.build", function()
	it("is deterministic (same stamp for same inputs)", function()
		expect(build().stamp).toBe(build().stamp)
		expect(#build().stamp > 0).toBe(true)
	end)

	it("Dark theme tokens equal the default style values exactly", function()
		local model = build()
		local dark = model.themes[1]
		expect(dark.name).toBe("Dark")
		local c, x = default_style.colors, default_style.extra
		local cases = {
			{ "Surface", c.surface },
			{ "SurfaceStrong", c.surfaceStrong },
			{ "Content", c.content },
			{ "ContentStrong", c.contentStrong },
			{ "Accent", c.accent },
			{ "OnAccent", c.onAccent },
			{ "Control", x.control },
			{ "ControlHover", x.controlHover },
			{ "ControlPressed", x.controlPressed },
			{ "ControlSelected", x.controlSelected },
			{ "ContentSecondary", x.contentSecondary },
			{ "Hairline", x.hairline },
		}
		for _, case in cases do
			local tok = dark.tokens[case[1] :: string]
			local src = case[2] :: any
			expect(tok ~= nil).toBe(true)
			expect(tok.r).toBe(src.r)
			expect(tok.g).toBe(src.g)
			expect(tok.b).toBe(src.b)
		end
	end)

	it("precomputes the accent interaction tokens with the edge's exact lerp", function()
		local model = build()
		local dark = model.themes[1]
		local a = default_style.colors.accent
		expect(math.abs(dark.tokens.AccentHover.r - (a.r + (1 - a.r) * 0.12)) < 1e-9).toBe(true)
		expect(math.abs(dark.tokens.AccentPressed.r - (a.r * (1 - 0.18))) < 1e-9).toBe(true)
	end)

	it("every theme passes the contrast gate (and a failing theme is rejected)", function()
		local model = build()
		for _, theme in model.themes do
			expect(theme.contrast.ok).toBe(true)
		end
		local bad = {
			colors = {
				surface = { r = 0.5, g = 0.5, b = 0.5 },
				content = { r = 0.55, g = 0.55, b = 0.55 }, -- ~1:1, fails
				surfaceStrong = { r = 1, g = 1, b = 1 },
				contentStrong = { r = 0, g = 0, b = 0 },
				accent = { r = 0, g = 0, b = 0.5 },
				onAccent = { r = 1, g = 1, b = 1 },
			},
			extra = default_style.extra,
			type = default_style.type,
			space = default_style.space,
			radii = default_style.radii,
			strokes = default_style.strokes,
			targetSizes = default_style.targetSizes,
			motion = default_style.motion,
		}
		local ok = pcall(function()
			sheet_model.build({ themes = { { name = "Bad", style = bad } } })
		end)
		expect(ok).toBe(false)
	end)

	it("orders state rules per the measured cascade (insertion order wins)", function()
		local model = build()
		-- selected < hover < pressed < disabled; surfaces before states
		expect(ruleIndex(model, "Selected row") < ruleIndex(model, "Control — hover")).toBe(true)
		expect(ruleIndex(model, "Control — hover") < ruleIndex(model, "Control — pressed")).toBe(true)
		expect(ruleIndex(model, "Control — pressed") < ruleIndex(model, "Disabled button")).toBe(true)
		expect(ruleIndex(model, "Control fill") < ruleIndex(model, "Selected row")).toBe(true)
		expect(ruleIndex(model, "Text default") < ruleIndex(model, "Base surface")).toBe(true)
	end)

	it("gates hover rules on the pointer-live tag (touch can never match)", function()
		local model = build()
		for _, rule in model.rules do
			if string.find(rule.selector, ":Hover", 1, true) ~= nil then
				expect(string.find(rule.selector, sheet_model.TAGS.pointerLive, 1, true) ~= nil).toBe(true)
			end
		end
	end)

	it("resolves every $token reference in every theme", function()
		local model = build()
		for _, rule in model.rules do
			for _, v in rule.props do
				if type(v) == "string" and string.sub(v, 1, 1) == "$" then
					local tokenName = string.sub(v, 2)
					for _, theme in model.themes do
						expect(theme.tokens[tokenName] ~= nil).toBe(true)
					end
				end
			end
		end
	end)

	it("names rules and tokens for humans (Style Editor surface)", function()
		local model = build()
		for _, rule in model.rules do
			-- readable: starts with an uppercase word, never a raw selector
			expect(string.match(rule.name, "^%u") ~= nil).toBe(true)
			expect(string.find(rule.name, "::") == nil).toBe(true)
			expect(string.find(rule.name, "luau%-") == nil).toBe(true)
		end
		for tokenName in model.themes[1].tokens do
			expect(string.match(tokenName, "^%u%w*$") ~= nil).toBe(true)
		end
	end)

	it("mirrors the layout-affecting tokens completely (read-only reference)", function()
		local model = build()
		local byName = {}
		for _, m in model.mirrors do
			byName[m.name] = m.value
		end
		expect(byName.SpaceXs).toBe(default_style.space.xs)
		expect(byName.SpaceM).toBe(default_style.space.m)
		expect(byName.SpaceXl).toBe(default_style.space.xl)
		expect(byName.TypeBody).toBe(default_style.type.body)
		expect(byName.TypeTitle).toBe(default_style.type.title)
		expect(byName.RadiusControl).toBe(default_style.radii.control)
		expect(byName.RadiusPanel).toBe(default_style.radii.panel)
		expect(byName.TargetMinimum).toBe(default_style.targetSizes.minimum)
		expect(byName.MotionFast).toBe(default_style.motion.fast)
		expect(byName.MotionNormal).toBe(default_style.motion.normal)
	end)

	it("declares transitions only on state rules, with known motion tokens", function()
		local model = build()
		for _, rule in model.rules do
			if rule.transitions ~= nil then
				for _, motionToken in rule.transitions do
					expect(model.motion[motionToken] ~= nil).toBe(true)
				end
			end
		end
	end)

	it("classifyTags: the pure hint->tag mapping the native adapter applies", function()
		local T = sheet_model.TAGS
		-- resting interactive control (Button/Toggle default)
		local rest = sheet_model.classifyTags({ surface = "control", interactive = true })
		expect(rest[T.surfacePrefix .. "control"]).toBe(true)
		expect(rest[T.interactive]).toBe(true)
		expect(rest[T.pointerLive]).toBe(nil)
		-- pointer-live only rides interactive (the hover gate)
		local live = sheet_model.classifyTags({ surface = "control", interactive = true, pointerLive = true })
		expect(live[T.pointerLive]).toBe(true)
		local liveNotInteractive = sheet_model.classifyTags({ surface = "control", pointerLive = true })
		expect(liveNotInteractive[T.pointerLive]).toBe(nil)
		-- scrim suppresses interaction chrome but keeps its surface
		local scrim =
			sheet_model.classifyTags({ surface = "scrim", interactive = true, selected = true, pointerLive = true })
		expect(scrim[T.surfacePrefix .. "scrim"]).toBe(true)
		expect(scrim[T.interactive]).toBe(nil)
		expect(scrim[T.selected]).toBe(nil)
		expect(scrim[T.pointerLive]).toBe(nil)
		-- plain is chrome-less: NO surface tag at all
		local plain = sheet_model.classifyTags({ surface = "plain", interactive = true })
		local count = 0
		for _ in plain do
			count += 1
		end
		expect(count).toBe(0)
		-- grip focus rides its own tag (native focus visual for Grip slivers)
		local grip = sheet_model.classifyTags({ gripFocus = true })
		expect(grip["luau-grip-focus"]).toBe(true)
		expect(sheet_model.classifyTags({ gripFocus = false })["luau-grip-focus"]).toBe(nil)
		-- selected + roles
		local sel = sheet_model.classifyTags({
			surface = "control",
			interactive = true,
			selected = true,
			strong = true,
			roleSecondary = true,
		})
		expect(sel[T.selected]).toBe(true)
		expect(sel["luau-role-strong"]).toBe(true)
		expect(sel["luau-role-secondary"]).toBe(true)
	end)

	it("builds a single-theme sheet from a custom game style (default-flip path)", function()
		-- a game passing its own compiled style (NOT Studio Neutral) gets a
		-- one-theme model whose tokens are that game's values
		local tokens = require("../src/tokens/tokens")
		local custom = {
			colors = {
				surface = { r = 0.05, g = 0.02, b = 0.08 },
				surfaceStrong = { r = 0.12, g = 0.06, b = 0.18 },
				content = { r = 0.95, g = 0.92, b = 0.99 },
				contentStrong = { r = 1, g = 1, b = 1 },
				accent = { r = 0.85, g = 0.35, b = 0.1 },
				onAccent = { r = 0, g = 0, b = 0 },
			},
			type = default_style.type,
			space = default_style.space,
			radii = { control = 4, panel = 10, pill = 999 },
			strokes = { hairline = 2 },
			targetSizes = default_style.targetSizes,
			motion = { fast = 0.1, normal = 0.25 },
		}
		local compiled, report = tokens.compile(custom)
		expect(compiled ~= nil).toBe(true)
		local style = compiled :: any
		local withExtra = table.clone(style)
		withExtra.extra = default_style.extra -- games may reuse the neutral extras
		local model = sheet_model.build({ themes = { { name = "Game", style = withExtra } } })
		expect(#model.themes).toBe(1)
		expect(model.defaultTheme).toBe("Game")
		expect(model.themes[1].tokens.Surface.r).toBe(0.05)
		expect(model.themes[1].tokens.Accent.g).toBe(0.35)
		-- game radii/strokes flow into the chrome rules
		local found = false
		for _, rule in model.rules do
			if rule.name == "Raised panel — corner" then
				found = true
				expect(rule.props.CornerRadius.offset).toBe(10)
			end
		end
		expect(found).toBe(true)
	end)

	it("exports the frozen tag vocabulary the adapter classifies with", function()
		expect(sheet_model.TAGS.selected).toBe("luau-selected")
		expect(sheet_model.TAGS.pointerLive).toBe("luau-pointer-live")
		expect(sheet_model.TAGS.interactive).toBe("luau-interactive")
		expect(sheet_model.TAGS.surfacePrefix).toBe("luau-surface-")
		expect(table.isfrozen(sheet_model.TAGS :: any)).toBe(true)
	end)
end)

-- ===== RS-A16-D4: THE BUILT-IN DEFAULT PAINTS ITS VALUE CONTROLS ============
--
-- Found live at stamp `1de8a15c-1722217` with native paint authority on and NO
-- package installed — the built-in studio-neutral default, which is five of the
-- nineteen matrix rows. The four `OWN_PAINT_SLOTS` surfaces were selected by no
-- rule in the live sheet, so `Frame default` (BackgroundTransparency = 1) won and
-- the Download bar was pixel-identical at 0% and 100% while the Brightness slider
-- had no rail and no thumb. `buildPackage` emitted the family; `build` — the
-- builder screen_target uses when no package is installed — did not.
--
-- These assert over the BASE model, which is the sheet that is actually live for
-- an unskinned screen. Every value is checked against the token the ADAPTER's
-- bespoke path writes for the same slot (src/client/screen_chrome.luau's
-- `chromeFillOf`), because those two paths are the same product decision seen
-- from the two paint authorities.

local BASE_SLOT_FILL: { [string]: any } = {
	sliderTrack = { token = "$Control", from = default_style.extra.control },
	sliderThumb = { token = "$SurfaceStrong", from = default_style.colors.surfaceStrong },
	barTrack = { token = "$Control", from = default_style.extra.control },
	barFill = { token = "$Accent", from = default_style.colors.accent },
	-- the indeterminate spinner's dot (parity round 2 §3.1): an unskinned
	-- spinner is a ring of accent dots, so it carries barFill's own flat truth
	spinner = { token = "$Accent", from = default_style.colors.accent },
}

local function baseRule(name: string): any
	for _, rule in build().rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

describe("build: the value-control own-paint family (RS-A16-D4)", function()
	it("selects every OWN_PAINT slot with a SOLID fill, in the base seed", function()
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			local rule = baseRule(`Slot — {slot}`)
			expect(rule ~= nil).toBe(true)
			-- the selector is the tag the renderer really applies, not a hopeful one
			local tag = chrome_slots.slotTagFor(slot)
			expect(rule.selector).toBe(`.{tag}`)
			expect(sheet_model.classifyTags({ slotHint = slot })[tag]).toBe(true)
			expect(rule.props.BackgroundTransparency.value).toBe(0)
			expect(rule.props.BackgroundColor3).toBe(BASE_SLOT_FILL[slot].token)
		end
	end)

	it("paints the token the BESPOKE path writes for the same slot", function()
		-- the live control experiment: with native paint off the adapter wrote
		-- barTrack #292d3a, barFill #2c62d2, sliderTrack #292d3a, sliderThumb
		-- #1c1f28. The rules have to resolve to those same colours or the two
		-- authorities disagree about what a flat value control looks like.
		local dark = build().themes[1]
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			local expected = BASE_SLOT_FILL[slot]
			local token = dark.tokens[string.sub(expected.token, 2)]
			expect(token.r).toBe(expected.from.r)
			expect(token.g).toBe(expected.from.g)
			expect(token.b).toBe(expected.from.b)
		end
	end)

	it("gives each slot the phantom corner and hairline the package path gives it", function()
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			local tag = chrome_slots.slotTagFor(slot)
			local corner = baseRule(`Slot — {slot} corner`)
			expect(corner ~= nil).toBe(true)
			expect(corner.selector).toBe(`.{tag}::UICorner`)
			if slot == "sliderThumb" or slot == "spinner" then
				-- a thumb and a spinner dot are CIRCLES: a square fallback reads as a
				-- different control, not as a degraded one (sheet_model's SLOT_ROUND)
				expect(corner.props.CornerRadius.scale).toBe(0.5)
				expect(corner.props.CornerRadius.offset).toBe(0)
			else
				expect(corner.props.CornerRadius.scale).toBe(0)
				expect(corner.props.CornerRadius.offset).toBe(default_style.radii.control)
			end
			local outline = baseRule(`Slot — {slot} outline`)
			expect(outline ~= nil).toBe(true)
			expect(outline.selector).toBe(`.{tag}::UIStroke`)
			expect(outline.props.Color).toBe("$Hairline")
			expect(outline.props.Transparency.value).toBe(default_style.extra.hairlineOpacity)
			expect(outline.props.Thickness.value).toBe(default_style.strokes.hairline)
		end
	end)

	it("pre-arms the skinned suppression, so a rung-2 override has a rule with NO package", function()
		-- `planFor(nil, slot, { image = ... })` returns a plan: a Slider's
		-- `thumbImage` skins a node with nothing installed, so the node earns
		-- `luau-skinned-<slot>` under the BASE sheet and needs the rule there.
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			local plan = chrome_slots.planFor(nil, slot, { image = "rbxassetid://991" })
			expect(plan ~= nil).toBe(true)
			expect(plan.localOverride).toBe(true)
			local skinnedTag = chrome_slots.skinnedTagFor(slot)
			expect(sheet_model.classifyTags({ skinnedSlot = slot })[skinnedTag]).toBe(true)
			local plate = baseRule(`Skinned — {slot}`)
			expect(plate ~= nil).toBe(true)
			expect(plate.selector).toBe(`.{skinnedTag}`)
			expect(plate.props.BackgroundTransparency.value).toBe(1)
			local corner = baseRule(`Skinned — {slot} corner`)
			expect(corner.props.CornerRadius.offset).toBe(0)
			expect(corner.props.CornerRadius.scale).toBe(0)
			local outline = baseRule(`Skinned — {slot} outline`)
			expect(outline.props.Thickness.value).toBe(0)
			expect(outline.props.Transparency.value).toBe(1)
		end
	end)

	it("orders paint, then suppression, inside the same cascade window as the package path", function()
		local model = build()
		-- the cascade is Priority then INSERTION ORDER, with no specificity, so
		-- these positions ARE the behaviour: the class default must lose to the
		-- paint, the paint must lose to art and to the focus accent, and the
		-- interaction states must still win over everything.
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(ruleIndex(model, "Frame default") < ruleIndex(model, `Slot — {slot}`)).toBe(true)
			expect(ruleIndex(model, `Slot — {slot}`) < ruleIndex(model, "Grip focus")).toBe(true)
			expect(ruleIndex(model, `Slot — {slot}`) < ruleIndex(model, `Skinned — {slot}`)).toBe(true)
			expect(ruleIndex(model, `Slot — {slot} corner`) < ruleIndex(model, `Skinned — {slot} corner`)).toBe(
				true
			)
			expect(ruleIndex(model, `Slot — {slot} outline`) < ruleIndex(model, `Skinned — {slot} outline`)).toBe(
				true
			)
			expect(ruleIndex(model, `Skinned — {slot}`) < ruleIndex(model, "Control — hover")).toBe(true)
		end
	end)

	it("emits each of the twelve names exactly ONCE (a rule name is identity)", function()
		local seen: { [string]: number } = {}
		for _, rule in build().rules do
			seen[rule.name] = (seen[rule.name] or 0) + 1
		end
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			for _, suffix in { "", " corner", " outline" } do
				expect(seen[`Slot — {slot}{suffix}`]).toBe(1)
				expect(seen[`Skinned — {slot}{suffix}`]).toBe(1)
			end
		end
	end)

	it("stays a LEGACY-shaped rule: no group, no priority", function()
		-- the shared emitter must not smuggle the package builder's explicit
		-- cascade fields into the legacy model (the materializer derives them)
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(baseRule(`Slot — {slot}`).group).toBeNil()
			expect(baseRule(`Slot — {slot}`).priority).toBeNil()
			expect(baseRule(`Skinned — {slot}`).group).toBeNil()
		end
	end)
end)

-- ===== REVIEW-FIX round: rule identity and scope ============================

local themes = require("../src/themes/package")
local snapshotLib = require("../src/themes/snapshot")

local function namesOf(model: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, rule in model.rules do
		set[rule.name] = true
	end
	return set
end

local function definePkg(mutate: ((def: any) -> ())?): any
	local def: any = {
		base = snapshotLib.neutralPackage(),
		identity = {
			id = "rule-names",
			displayName = "Rule Names",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Dark",
			themes = {
				{ name = "Dark", colors = default_style.colors, extra = default_style.extra },
			},
		},
	}
	if mutate ~= nil then
		mutate(def)
	end
	local pkg, report = themes.define(def)
	assert(pkg ~= nil, `fixture failed: {report.errors[1] and report.errors[1].message}`)
	return pkg
end

describe("buildPackage: a rule NAME is identity, so the vocabulary is shared (C16)", function()
	it("emits the legacy class-default names, never the engine class names", function()
		local package = namesOf(sheet_model.buildPackage(definePkg()))
		for _, name in
			{ "Frame default", "Label default", "Button default", "Image default", "Field default", "Scroll default" }
		do
			expect(package[name]).toBe(true)
		end
		for _, name in
			{
				"TextLabel default",
				"TextButton default",
				"ImageLabel default",
				"TextBox default",
				"ScrollingFrame default",
			}
		do
			expect(package[name]).toBeNil()
		end
	end)

	it("every rule the legacy builder names is named identically by buildPackage", function()
		-- a renamed rule reads as a deleted rule plus a new one: a designer's saved
		-- edit is orphaned and every setRuleProperty push silently misses
		local legacy = build()
		local package = namesOf(sheet_model.buildPackage(definePkg()))
		local shared = 0
		for _, rule in legacy.rules do
			expect(package[rule.name]).toBe(true)
			shared += 1
		end
		expect(shared >= 40).toBe(true)
	end)

	it("ONE emitter: the value-slot family is byte-identical in both builders (RS-A16-D4)", function()
		-- The defect was a COPY that only one builder ran. So the guard is not
		-- "both have a rule called X" but "both rules are the same rule": same
		-- selector, same prop keys, same values. A future divergence — a different
		-- token, a square thumb on one path — fails here rather than on a device.
		local legacy: { [string]: any } = {}
		for _, rule in build().rules do
			legacy[rule.name] = rule
		end
		local flat: { [string]: any } = {}
		for _, rule in sheet_model.buildPackage(snapshotLib.neutralPackage()).rules do
			flat[rule.name] = rule
		end
		local checked = 0
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			for _, name in
				{
					`Slot — {slot}`,
					`Slot — {slot} corner`,
					`Slot — {slot} outline`,
					`Skinned — {slot}`,
					`Skinned — {slot} corner`,
					`Skinned — {slot} outline`,
				}
			do
				local a, b = legacy[name], flat[name]
				expect(a ~= nil).toBe(true)
				expect(b ~= nil).toBe(true)
				expect(a.selector).toBe(b.selector)
				for prop, value in a.props do
					local other = b.props[prop]
					expect(other ~= nil).toBe(true)
					if type(value) == "string" then
						expect(other).toBe(value)
					else
						expect(other.kind).toBe(value.kind)
						expect(other.value).toBe(value.value)
						expect(other.scale).toBe(value.scale)
						expect(other.offset).toBe(value.offset)
					end
				end
				for prop in b.props do
					expect(a.props[prop] ~= nil).toBe(true)
				end
				checked += 1
			end
		end
		expect(checked).toBe(6 * #chrome_slots.OWN_PAINT_SLOTS)
	end)

	it("the class-default vocabulary is exported as one table", function()
		expect(sheet_model.CLASS_DEFAULT_NAME.TextLabel).toBe("Label")
		expect(sheet_model.CLASS_DEFAULT_NAME.TextBox).toBe("Field")
		expect(sheet_model.CLASS_DEFAULT_NAME.ScrollingFrame).toBe("Scroll")
	end)
end)

describe("buildPackage: the chrome text lift paints on every skin that lifts (C17)", function()
	local function skinned(slot: string): any
		return definePkg(function(def)
			def.assets = {
				art = {
					contentId = "rbxassetid://9",
					sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
					sliceScale = 1,
					preload = "lazy",
					fallback = "native",
				},
			}
			def.chrome = {
				panel = { kind = "native" },
				control = { kind = "native" },
				field = { kind = "native" },
				selection = { kind = "native" },
				divider = { kind = "native" },
				scrollbar = { kind = "native" },
			}
			def.chrome[slot] = {
				kind = "nineSlice",
				asset = "art",
				contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
				fallback = "native",
			}
		end)
	end

	it("a SELECTION-only skin still emits the lift rules (it lifts TextButton labels)", function()
		local names = namesOf(sheet_model.buildPackage(skinned("selection")))
		expect(names["Chrome text — button font"]).toBe(true)
		expect(names["Chrome text — accent"]).toBe(true)
		expect(names["Chrome text — disabled button"]).toBe(true)
	end)

	it("a flat theme emits none of them", function()
		local names = namesOf(sheet_model.buildPackage(definePkg()))
		expect(names["Chrome text — button font"]).toBeNil()
	end)

	it("the parent-role variants reach the lifted label through a child combinator", function()
		local model = sheet_model.buildPackage(skinned("control"))
		local byName: { [string]: any } = {}
		for _, rule in model.rules do
			byName[rule.name] = rule
		end
		local strong = byName["Chrome text — strong"]
		expect(strong ~= nil).toBe(true)
		expect(strong.selector).toBe(".luau-role-strong > .luau-chrome-text")
		expect(strong.props.TextColor3).toBe("$ContentStrong")
		local secondary = byName["Chrome text — parent secondary"]
		expect(secondary ~= nil).toBe(true)
		expect(secondary.selector).toBe(".luau-role-secondary > .luau-chrome-text")
		expect(secondary.props.TextColor3).toBe("$ContentSecondary")
		-- the label's OWN placeholder tag keeps its rule too
		expect(byName["Chrome text — secondary"].selector).toBe(".luau-chrome-text.luau-role-secondary")
	end)

	it("the editing yield goes FULLY transparent so the caret and text show", function()
		local model = sheet_model.buildPackage(skinned("field"))
		local editing: any = nil
		for _, rule in model.rules do
			if rule.name == "Chrome — field editing" then
				editing = rule
			end
		end
		expect(editing ~= nil).toBe(true)
		expect(editing.props.ImageTransparency.value).toBe(1)
		-- an opaque child covers the parent's engine-drawn text under Sibling
		expect(editing.props.BackgroundTransparency.value).toBe(1)
		expect(editing.props.BackgroundColor3).toBeNil()
	end)
end)

describe("buildPackage: an author rule earns chrome scope by SELECTOR (C20)", function()
	it("rejects an image property on a rule that names no chrome slot", function()
		expect(function()
			sheet_model.buildPackage(definePkg(), {
				rules = {
					{
						name = "Author — bad",
						selector = ".luau-surface-raised",
						props = { Image = "rbxassetid://1" },
					},
				},
			})
		end).toThrow()
	end)

	it("accepts the same property on a rule that does name one", function()
		local model = sheet_model.buildPackage(definePkg(), {
			rules = {
				{
					name = "Author — good",
					selector = ".luau-chrome-panel",
					props = { ImageTransparency = { kind = "number", value = 0.5 } },
				},
			},
		})
		expect(namesOf(model)["Author — good"]).toBe(true)
	end)

	it("an author rule with a plain paint property is always fine", function()
		local model = sheet_model.buildPackage(definePkg(), {
			rules = {
				{
					name = "Author — paint",
					selector = ".luau-surface-base",
					props = { BackgroundColor3 = "$Accent" },
				},
			},
		})
		expect(namesOf(model)["Author — paint"]).toBe(true)
	end)
end)

-- ===========================================================================
-- DIRECTOR ROUND 8 / 10 / 11 (2026-07-26) — three native-mode phantom-modifier
-- and palette-pairing defects, all found live and all in the ONE place a rule
-- can express them.
-- ===========================================================================

describe("RS-DIR10: a phantom ::UIStroke strokes the TEXT unless the rule says Border", function()
	-- FOUND LIVE (stamp 66599d58-1744436, classic-desktop Day): `UIStroke`'s
	-- engine default `ApplyStrokeMode` is CONTEXTUAL, which on a TextButton/
	-- TextLabel strokes the GLYPHS and not the border. The bespoke path sets
	-- Border explicitly (`hairline()` in screen_target); every rule-owned stroke
	-- inherited the engine default instead, so a chip's outline never drew and
	-- its label grew a hairline-coloured halo. Under Studio Neutral the hairline
	-- is white on white text, which is why it hid for two whole stages.
	local function strokeRules(model: any): { any }
		local out = {}
		for _, r in model.rules do
			if string.find(r.selector, "::UIStroke", 1, true) ~= nil then
				table.insert(out, r)
			end
		end
		return out
	end

	local function assertBorder(model: any, label: string)
		local rules = strokeRules(model)
		expect(#rules >= 3).toBe(true)
		for _, r in rules do
			local mode = r.props.ApplyStrokeMode
			-- name the offender in the failure, not just "expected true"
			expect(`{label}/{r.name}: {if mode == nil then "NO ApplyStrokeMode" else "ok"}`).toBe(
				`{label}/{r.name}: ok`
			)
			expect(type(mode) == "table").toBe(true)
			expect(mode.kind).toBe("enum")
			expect(mode.enum).toBe("ApplyStrokeMode")
			expect(mode.item).toBe("Border")
		end
	end

	it("every ::UIStroke rule the base seed emits carries ApplyStrokeMode = Border", function()
		assertBorder(build(), "build")
	end)

	it("every ::UIStroke rule a package emits carries ApplyStrokeMode = Border", function()
		assertBorder(sheet_model.buildPackage(definePkg()), "buildPackage")
	end)

	it("ApplyStrokeMode is a legal phantom property, so the rule cannot be inert", function()
		expect(sheet_model.PHANTOM_PROPS.UIStroke.ApplyStrokeMode).toBe(true)
	end)
end)

describe("RS-DIR11: the accent surface keeps the corner every other surface has", function()
	-- FOUND LIVE under glossy-mobile (radii.control = 16): a SELECTED picker chip
	-- swaps `surface = chip` for `surface = accent`, and the accent rule set
	-- carried a fill and a label colour and NO ::UICorner — per-surface rules
	-- REPLACE, they do not compose — so the selected button went hard square
	-- while every sibling stayed a pill. The bespoke path never had it: a Button
	-- gets a REAL UICorner from `wireInteractiveStates` before applySurface runs.
	local function ruleNamed(model: any, name: string): any
		for _, r in model.rules do
			if r.name == name then
				return r
			end
		end
		return nil
	end

	it("the base seed emits Primary button — corner at radii.control", function()
		local rule = ruleNamed(build(), "Primary button — corner")
		expect(rule ~= nil).toBe(true)
		expect(rule.selector).toBe(".luau-surface-accent::UICorner")
		expect(rule.props.CornerRadius.kind).toBe("udim")
		expect(rule.props.CornerRadius.offset).toBe(default_style.radii.control)
	end)

	it("a package emits it too, from ITS radii, and a live metric edit repaints it", function()
		local model = sheet_model.buildPackage(definePkg())
		local rule = ruleNamed(model, "Primary button — corner")
		expect(rule ~= nil).toBe(true)
		expect(rule.selector).toBe(".luau-surface-accent::UICorner")
		local wired = false
		for _, entry in model.metricRuleProps or {} do
			if entry.rule == "Primary button — corner" and entry.path == "radii.control" then
				wired = true
			end
		end
		expect(wired).toBe(true)
	end)

	it("it sits with the other surface corners, so the skinned suppression still wins", function()
		local model = sheet_model.buildPackage(definePkg())
		local corner, suppression = nil, nil
		for i, r in model.rules do
			if r.name == "Primary button — corner" then
				corner = i
			elseif r.name == "Skinned — barTrack corner" then
				suppression = i
			end
		end
		expect(corner ~= nil).toBe(true)
		expect(suppression ~= nil).toBe(true)
		expect((corner :: any) < (suppression :: any)).toBe(true)
	end)
end)

describe("RS-DIR8: a selected surface pairs with a content colour that can be read on it", function()
	-- FOUND LIVE under glossy-touch: the segmented "Balanced" option drew
	-- $Content (a near-black navy) on its selected art, measured rgb(66,116,215)
	-- in the glyph band — 3.74:1, under the 4.5 floor. ADR-0019 gates
	-- accent/onAccent as the one guaranteed pair; nothing carried that pairing to
	-- the SELECTED state, so the lifted label kept the default content colour.
	local function tokenOf(model: any, themeName: string, key: string): any
		for _, theme in model.themes do
			if theme.name == themeName then
				return theme.tokens[key]
			end
		end
		return nil
	end

	it("selectedContentColor prefers content and switches only when content fails the floor", function()
		local dark = { colors = default_style.colors, extra = default_style.extra }
		local picked = sheet_model.selectedContentColor(dark)
		-- Studio Neutral's own selected surface reads content at 9.74:1 — the
		-- status quo, and the reason the flat baseline cannot move
		expect(picked.r).toBe(default_style.colors.content.r)
		expect(picked.g).toBe(default_style.colors.content.g)
		expect(picked.b).toBe(default_style.colors.content.b)

		-- a gold selected plate: content 1.75:1, onAccent 8.47:1 (pixel-quest's
		-- real numbers), so the guaranteed partner takes over
		local gold = {
			colors = {
				surface = { r = 0.1, g = 0.1, b = 0.1 },
				surfaceStrong = { r = 0.15, g = 0.15, b = 0.15 },
				content = { r = 0.95, g = 0.95, b = 0.9 },
				contentStrong = { r = 1, g = 1, b = 1 },
				accent = { r = 0.84, g = 0.66, b = 0.38 },
				onAccent = { r = 0.08, g = 0.06, b = 0.03 },
			},
			extra = { controlSelected = { r = 0.84, g = 0.66, b = 0.38 } },
		}
		local goldPick = sheet_model.selectedContentColor(gold)
		expect(goldPick.r).toBe(gold.colors.onAccent.r)
		expect(goldPick.b).toBe(gold.colors.onAccent.b)
	end)

	it("$OnSelected is a real token on every theme of both builders", function()
		local legacy = build()
		expect(tokenOf(legacy, "Dark", "OnSelected") ~= nil).toBe(true)
		expect(tokenOf(legacy, "Light", "OnSelected") ~= nil).toBe(true)
		local package = sheet_model.buildPackage(definePkg())
		expect(tokenOf(package, "Dark", "OnSelected") ~= nil).toBe(true)
	end)

	it("the lifted label of a SELECTED skinned node resolves it", function()
		local model = sheet_model.buildPackage(definePkg(function(def)
			def.assets = {
				plate = { content = "rbxassetid://1", sliceCenter = { x0 = 4, y0 = 4, x1 = 12, y1 = 12 } },
			}
			def.chrome = {
				selection = {
					kind = "nineSlice",
					asset = { default = "plate", selected = "plate" },
					contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
					fallback = "native",
				},
			}
		end))
		local selectedAt, accentAt = nil, nil
		for i, r in model.rules do
			if r.name == "Chrome text — selected" then
				selectedAt = i
				expect(r.selector).toBe(".luau-selected > .luau-chrome-text")
				expect(r.props.TextColor3).toBe("$OnSelected")
			elseif r.name == "Chrome text — accent" then
				accentAt = i
			end
		end
		expect(selectedAt ~= nil).toBe(true)
		-- BEFORE the role/surface text rules, mirroring the ART order: a role tint
		-- rule beats the selected tint on the picture, so it beats it on the label
		expect(accentAt ~= nil).toBe(true)
		expect((selectedAt :: any) < (accentAt :: any)).toBe(true)
	end)

	it("the UNSKINNED selected row resolves the same token in both builders", function()
		for _, model in { build(), sheet_model.buildPackage(definePkg()) } do
			local found = false
			for _, r in model.rules do
				if r.name == "Selected row" then
					found = true
					expect(r.props.BackgroundColor3).toBe("$ControlSelected")
					expect(r.props.TextColor3).toBe("$OnSelected")
				end
			end
			expect(found).toBe(true)
		end
	end)
end)

describe("RS-DIR8 sweep: every reference package's selected state is readable", function()
	-- The director asked for the sweep by name, and it is the half a resolver
	-- cannot do for itself: `selectedContentColor` picks the BETTER of two
	-- colours, and a theme whose selected surface can carry NEITHER would still
	-- get an answer. This is the gate that says one of them has to work.
	local themesApi = require("../src") :: any
	local MODULES = {
		"classic_desktop",
		"compact_pointer",
		"fantasy_ornate",
		"fantasy_parchment",
		"fantasy_parchment_stub",
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"scifi_hud",
	}

	it("a readable content role exists on every theme of every reference package", function()
		local checked = 0
		local rescued = {}
		local entries: { { id: string, pkg: any } } = {
			{ id = "studio-neutral", pkg = snapshotLib.neutralPackage() },
		}
		for _, name in MODULES do
			local module = require(`../examples/themes/{name}`) :: any
			table.insert(entries, { id = module.id, pkg = (module.build(themesApi.themes)) })
		end
		for _, entry in entries do
			for _, theme in entry.pkg.style.themes do
				local report = sheet_model.selectedPairReport(theme)
				-- name the offender: a bare `expect(true)` here would be unfixable
				expect(`{entry.id}/{theme.name}: {if report.ok then "readable" else "UNREADABLE"}`).toBe(
					`{entry.id}/{theme.name}: readable`
				)
				if report.picked == "onAccent" then
					table.insert(rescued, `{entry.id}/{theme.name}`)
				end
				checked += 1
			end
		end
		expect(checked >= 13).toBe(true)
		-- the two the sweep actually MOVES, recorded so a silent third is visible
		-- in the diff rather than only in a live capture
		table.sort(rescued)
		expect(table.concat(rescued, ", ")).toBe("glossy-touch/Sky, pixel-quest/Quest")
	end)

	it("the flat default is untouched: Studio Neutral still reads $Content", function()
		local neutral = snapshotLib.neutralPackage()
		local report = sheet_model.selectedPairReport(neutral.style.themes[1])
		expect(report.picked).toBe("content")
		expect(report.content >= 4.5).toBe(true)
	end)
end)
