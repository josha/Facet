--!strict
--[[ THE PLAYER'S BACKGROUND-TRANSPARENCY PREFERENCE, HONOURED BY A PAINT PATH
	(owed row O-26, ADR-0035).

	`GuiService.PreferredTransparency` reaches Facet as the `preferredTransparency`
	fact and the `effectiveTransparency` memo, and for four stages NOTHING read it —
	the one accessibility preference the framework published and did not honour.
	These are the pins that close it.

	WHAT THE ROW IS NOT. It is not "multiply every transparency in the framework by
	a factor". The arithmetic alone refuses that (case 4 below): the engine's
	`BackgroundTransparency = 1` means INVISIBLE, so scaling it by a preference of
	0.5 paints every hidden plate in the tree at half opacity. Roblox's own
	recommendation is scoped the same way — its example TAGS the elements that mean
	to be see-through rather than sweeping the tree.

	SO THE SCOPE IS A MEASUREMENT, NOT A TASTE CALL. Case 3 walks the whole
	generated sheet and asserts what the audit found: `Scrim backdrop` is the ONLY
	rule in Facet's painted output whose `BackgroundTransparency` is strictly
	between 0 and 1. Every other framework background is already opaque or already
	invisible, and the preference is a **Background** Transparency setting.

	THE REFUSALS ARE PINNED TOO (cases 5-7), because a refusal nobody asserts is an
	oversight waiting to be "fixed": the disabled dim is SEMANTIC (the alpha is the
	state), the hairline is a BORDER not a background, and an authored `opacity` is
	the AUTHOR's number — scaling it would retarget a running `withAnimation`.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

local function build()
	return sheet_model.build({
		themes = {
			{ name = "Dark", style = default_style },
			{ name = "Light", style = light_style },
		},
	})
end

-- the compiled Studio Neutral package, the shipped path (the `packageWith` idiom
-- every other package spec uses)
local function neutralPackage(): any
	return (
		themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "preferred-transparency-test",
				displayName = "Preferred Transparency Test",
				schemaVersion = themes.SCHEMA,
				version = "1.0.0",
			},
		})
	)
end

-- ===========================================================================
-- 1-2. the composition itself: the platform's own documented recipe
-- ===========================================================================
describe("the preference composes with a theme's backdrop alpha, and nothing else", function()
	--[[ Roblox states the recipe in the property's own reference page:
		"Multiplying a UI element's BackgroundTransparency with PreferredTransparency
		is the recommended approach, such that backgrounds become more opaque as
		PreferredTransparency approaches 0."  A value of 1 is the default (paint what
		the theme said); 0 is "fully opaque". ]]
	it("is base x preference — 1 is the identity and 0 is fully opaque", function()
		expect(sheet_model.backdropTransparency(0.45, 1)).toBe(0.45)
		expect(sheet_model.backdropTransparency(0.45, 0)).toBe(0)
		expect(sheet_model.backdropTransparency(0.45, 0.5)).toBe(0.225)
		-- a theme that dims harder keeps its RELATIVE intent under the preference
		expect(sheet_model.backdropTransparency(0.62, 0.5)).toBe(0.31)
	end)

	--[[ The env memo already clamps garbage into 0..1, but this function is also
		called from the adapter with a value that crossed a seam, and a paint that
		takes a NaN is a paint nobody can see. Identity on garbage, never a change. ]]
	it("a garbage preference is the IDENTITY, never a silent paint change", function()
		local base = 0.45
		expect(sheet_model.backdropTransparency(base, 0 / 0)).toBe(base)
		expect(sheet_model.backdropTransparency(base, nil :: any)).toBe(base)
		expect(sheet_model.backdropTransparency(base, "0.2" :: any)).toBe(base)
		-- out of domain clamps rather than propagating: 2 would BRIGHTEN the dim
		expect(sheet_model.backdropTransparency(base, 2)).toBe(base)
		expect(sheet_model.backdropTransparency(base, -1)).toBe(0)
	end)
end)

-- ===========================================================================
-- 3. THE SCOPE, as an invariant over the whole sheet rather than a spot check
-- ===========================================================================
describe("the scope is a measurement: one partial background in the whole sheet", function()
	local function partialBackgrounds(model: any): { string }
		local found: { string } = {}
		for _, rule in model.rules do
			local prop = rule.props.BackgroundTransparency
			if type(prop) == "table" and prop.kind == "number" then
				if prop.value > 0 and prop.value < 1 then
					table.insert(found, `{rule.name}={prop.value}`)
				end
			end
		end
		table.sort(found)
		return found
	end

	it("the ONLY rule painting a see-through background is the backdrop", function()
		expect(table.concat(partialBackgrounds(build()), ", ")).toBe("Scrim backdrop=0.45")
	end)

	--[[ ...and the same holds for a compiled THEME PACKAGE, which is the shipped
		path. A package may dim harder or softer; it may not invent a second
		translucent background without this reddening. ]]
	it("...and in a compiled theme package too, whatever its own dim is", function()
		local found = partialBackgrounds(sheet_model.buildPackage(neutralPackage()))
		expect(#found).toBe(1)
		expect(string.match(found[1], "^Scrim backdrop=") ~= nil).toBe(true)
	end)

	--[[ THE DECLARED SCOPE, ASSERTED AGAINST THE MEASURED ONE. `PREFERENCE_RULE_PROPS`
		is what the adapter will actually patch; the walk above is what the sheet
		actually paints. Comparing the two is what makes "multiply everything" unable
		to arrive by the back door in EITHER direction — a new translucent background
		with no decision reddens, and a new patch entry with nothing translucent to
		patch reddens too. ]]
	it("the declared patch scope is exactly the measured set of translucent backgrounds", function()
		local declared: { string } = {}
		for _, entry in sheet_model.PREFERENCE_RULE_PROPS do
			expect(entry.prop).toBe("BackgroundTransparency")
			table.insert(declared, entry.rule)
		end
		table.sort(declared)

		local measured: { string } = {}
		for _, rule in build().rules do
			local prop = rule.props.BackgroundTransparency
			if type(prop) == "table" and prop.kind == "number" and prop.value > 0 and prop.value < 1 then
				table.insert(measured, rule.name)
			end
		end
		table.sort(measured)

		expect(table.concat(declared, ", ")).toBe(table.concat(measured, ", "))
		expect(#declared).toBe(1)
		expect(declared[1]).toBe(sheet_model.SCRIM_RULE)
	end)

	it("...and the same rule name is the one BOTH builders emit, so a package is covered too", function()
		local function hasScrimRule(model: any): boolean
			for _, r in model.rules do
				if r.name == sheet_model.SCRIM_RULE then
					return true
				end
			end
			return false
		end
		expect(hasScrimRule(build())).toBe(true)
		expect(hasScrimRule(sheet_model.buildPackage(neutralPackage()))).toBe(true)
	end)
end)

-- ===========================================================================
-- 4. the arithmetic that makes "scale every transparency" wrong
-- ===========================================================================
describe("why the sweep is refused rather than merely unfashionable", function()
	--[[ This is the whole argument in two numbers. In the engine, transparency 1 is
		INVISIBLE, so the naive sweep does not make hidden things more opaque — it
		makes them APPEAR. Facet's class-default rules exist precisely to hold every
		Frame/Label/Button/Image/Field/Scroll background at 1 ("invisible until a
		surface says otherwise" is itself sheet-owned), so a blanket multiply would
		paint a plate behind every label in every tree. ]]
	it("scaling an INVISIBLE background does not dim it, it reveals it", function()
		expect(sheet_model.backdropTransparency(1, 0.5)).toBe(0.5) -- the arithmetic
		local invisible = 0
		for _, rule in build().rules do
			local prop = rule.props.BackgroundTransparency
			if type(prop) == "table" and prop.kind == "number" and prop.value == 1 then
				invisible += 1
			end
		end
		-- ...and there are this many of them, which is the size of the accident
		expect(invisible >= 6).toBe(true)
		-- none of them is in the patch scope
		for _, entry in sheet_model.PREFERENCE_RULE_PROPS do
			expect(entry.rule).toBe(sheet_model.SCRIM_RULE)
		end
	end)
end)

-- ===========================================================================
-- 5-6. the refusals, by name
-- ===========================================================================
describe("the refusals: what the preference deliberately does not touch", function()
	--[[ SEMANTIC ALPHA. `disabledContentOpacity` is not a backdrop — the dim IS the
		disabled signal, and it is `TextTransparency`/`ImageTransparency`, which the
		native sheet owns. Honouring the preference there would delete an
		accessibility affordance in the name of an accessibility preference. ]]
	it("the DISABLED dim is untouched — the alpha there is the state, not a backdrop", function()
		local model = build()
		local seen: { string } = {}
		for _, rule in model.rules do
			for prop, value in rule.props do
				if
					(prop == "TextTransparency" or prop == "ImageTransparency")
					and type(value) == "table"
					and value.kind == "number"
					and value.value > 0
					and value.value < 1
				then
					table.insert(seen, rule.name)
				end
			end
		end
		expect(#seen > 0).toBe(true) -- the disabled rules really are partial
		for _, entry in sheet_model.PREFERENCE_RULE_PROPS do
			expect(entry.prop).toBe("BackgroundTransparency")
			expect(entry.rule).never().toBe(seen[1])
		end
	end)

	--[[ A BORDER IS NOT A BACKGROUND. The hairline is a `UIStroke.Transparency` at
		0.92 — a line drawn faintly over whatever it sits on. Solidifying it would be
		a CONTRAST change (the separate "increase contrast" preference, which
		Roblox does not surface), and the setting the player moved is named Background
		Transparency in the menu it lives in. ]]
	it("the HAIRLINE is untouched — a stroke is a border, and the setting names backgrounds", function()
		local model = build()
		local strokes = 0
		for _, rule in model.rules do
			local prop = rule.props.Transparency
			if type(prop) == "table" and prop.kind == "number" and prop.value > 0 and prop.value < 1 then
				strokes += 1
			end
		end
		expect(strokes > 0).toBe(true)
		for _, entry in sheet_model.PREFERENCE_RULE_PROPS do
			expect(entry.prop).never().toBe("Transparency")
		end
	end)
end)

-- ===========================================================================
-- 7. the authored-versus-presentation line
-- ===========================================================================
describe("an AUTHORED opacity is the author's number and the preference never scales it", function()
	--[[ ADR-0026 made `opacity` an authored term the presentation channel composes
		into `CanvasGroup.GroupTransparency`; ADR-0033's `withAnimation` interpolates
		that same term. If the preference scaled it, an author's explicit 0.5 would
		silently become something else AND a running fade would be retargeted
		mid-flight — the author's value and the player's preference fighting, which
		is exactly what ADR-0035 refuses. The preference scales tokens the FRAMEWORK
		declared as decoration; it never scales a number an author or an animation
		is driving. ]]
	local function opacityUnder(preference: number): number
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("preferredTransparency", preference)
		local adapter = fake_target.new()
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, adapter, system)
		pres.present(Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.ZStack({
					id = "Fade",
					opacity = 0.5,
					children = { Facet.UI.Text({ id = "Label", text = "hello" }) },
				}),
			},
		}))
		pres.refresh()
		local node = adapter.node("/S/Fade")
		return node.canvasGroupInstance.groupTransparency
	end

	it("opacity 0.5 stays 0.5 at every preference, including fully opaque", function()
		expect(opacityUnder(1)).toBe(opacityUnder(0))
		expect(opacityUnder(0.25)).toBe(opacityUnder(1))
	end)
end)

-- ===========================================================================
-- 8. the seam: the framework PUSHES the fact, it does not hope a consumer wires it
-- ===========================================================================
describe("the renderer pushes the preference at attach and on every change", function()
	local function world(initial: number?)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		if initial ~= nil then
			env:set("preferredTransparency", initial)
		end
		local adapter = fake_target.new()
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, adapter, system)
		pres.present(Facet.UI.Screen({ id = "S", children = { Facet.UI.Text({ id = "L", text = "x" }) } }))
		pres.refresh()
		return core, env, adapter
	end

	--[[ The `setReducedMotion` lesson, applied before it can be re-learned: that
		fact reached the adapter only through a construction-time closure that all
		FOUR production call sites forgot, so reduced motion silently did nothing for
		four stages. A preference that needs a consumer to wire it is a preference
		that does nothing, which is the whole of row O-26. ]]
	it("arrives at attach with no consumer wiring at all", function()
		local _, _, adapter = world(0.4)
		expect(adapter.preferredTransparency()).toBe(0.4)
	end)

	it("...and again when the player moves the setting mid-session", function()
		local _, env, adapter = world()
		expect(adapter.preferredTransparency()).toBe(1)
		env:set("preferredTransparency", 0)
		expect(adapter.preferredTransparency()).toBe(0)
		env:set("preferredTransparency", 0.75)
		expect(adapter.preferredTransparency()).toBe(0.75)
	end)

	it("a garbage platform fact never reaches the adapter — the memo clamps first", function()
		local _, env, adapter = world()
		env:set("preferredTransparency", 0 / 0)
		expect(adapter.preferredTransparency()).toBe(1)
		env:set("preferredTransparency", 5)
		expect(adapter.preferredTransparency()).toBe(1)
	end)
end)

-- ===========================================================================
-- 9. one composition, two writers — the source contract
-- ===========================================================================
describe("the two paint modes compose the SAME number", function()
	--[[ `src/client/*` reaches engine globals at load, so the live adapter cannot
		run here; this is the same source-contract instrument every other adapter pin
		uses. The point it pins is the `DISABLED_CONTENT_OPACITY` shape: two writers
		(the native rule patch and the bespoke surface write), ONE composition
		function, so the modes cannot drift into disagreeing about what the player
		asked for. ]]
	it("the bespoke scrim write goes through backdropTransparency, not a bare token read", function()
		local paint = fs.readFile("src/client/screen_paint.luau")
		expect(string.find(paint, "sheet_model.backdropTransparency(", 1, true) ~= nil).toBe(true)
		-- and the raw token read it replaced is gone from the scrim branch
		expect(string.find(paint, "BackgroundTransparency = style.extra.scrimOpacity", 1, true)).toBe(nil)
	end)

	it("the native rule patch goes through it too, over the DECLARED scope", function()
		local target = fs.readFile("src/client/screen_target.luau")
		expect(string.find(target, "sheet_model.backdropTransparency(", 1, true) ~= nil).toBe(true)
		expect(string.find(target, "sheet_model.PREFERENCE_RULE_PROPS", 1, true) ~= nil).toBe(true)
	end)
end)
