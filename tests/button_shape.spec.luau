--!strict
-- THE CIRCLE BUTTON (`UI.Button{ shape = "circle" }`, feature round 2026-07-26).
--
-- The director's reference is the iOS floating round "…" action, and the whole
-- promise is that an author declares a SHAPE and never computes a size, a
-- radius, or a square. Four things therefore have to be true, and each is
-- asserted at the layer it can actually be wrong at:
--
--   1. the SCHEMA BOUNDARY refuses every declaration a disc cannot honour —
--      a multi-word drawn label, two authored axes, an icon on a rectangle,
--      a semantic name that means nothing — naming the field, the rule and
--      the fix, at construction rather than at paint;
--   2. the SOLVER enforces the 1:1 box from the control metric, so a metric
--      package resizes every disc and a pixel package snaps it;
--   3. the SHEET paints the pill and the rim through the same phantom
--      ::UICorner/::UIStroke machinery the slider thumb proved, with ONE rule
--      that beats every surface corner — a claim this file falsifies rather
--      than assumes (see "one rule is enough" below);
--   4. the CONTENT path — one semantic icon or up to three characters —
--      reaches the live adapter, not merely the emitted model.
--
-- Nothing existing may move: `shape` is absent from every Button that predates
-- it, and `check_flat_baseline` proves the flat render dump is unchanged.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local authority = require("../src/render/authority")
local schema = require("../src/blueprint_schema")
local snapshot = require("../src/themes/snapshot")
local themes = require("../src/themes/package")
local sheet_model = require("../src/tokens/sheet_model")
local defaultStyle = require("../src/tokens/default_style")
local fake_target = require("./lib/fake_target")
local frameworkIconRuleCount = require("../tests/lib/framework_icons")
local adapter_source = require("./lib/adapter_source")

-- the LIVE adapter as ONE text: it is three files since the 200k `Source`
-- write-cap split (tests/lib/adapter_source names them and says why)
local adapterSource = adapter_source.live()
-- the renderer as ONE text: two files since the 200k `Source` write-cap split
-- (tests/lib/renderer_source names them and says why)
local rendererSource = require("./lib/renderer_source").all()

local CIRCLE_TAG = sheet_model.TAGS.shapePrefix .. "circle"

local function render(screen: any, metrics: any?, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if metrics ~= nil then
		env:set("themeMetrics", metrics)
	end
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, core
end

local function rectOf(adapter: any, path: string): any
	local node = adapter.node(path)
	return if node ~= nil then node.rect else nil
end

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

-- a package built through the PUBLIC compiler, derived from Studio Neutral
-- exactly as a real theme author derives one, so the metric assertions below are
-- what a consumer would actually get
local function packageWith(metrics: any, identityExtra: any?): any
	local identity: any = {
		id = "circle-test",
		displayName = "Circle Test",
		schemaVersion = themes.SCHEMA,
		version = "1.0.0",
	}
	for k, v in identityExtra or {} do
		identity[k] = v
	end
	return (themes.define({
		base = snapshot.neutralPackage(),
		identity = identity,
		metrics = metrics,
	}))
end

-- ===========================================================================
-- 1. THE SCHEMA BOUNDARY
-- ===========================================================================

describe("circle Button: the accept classes", function()
	it("takes shape = circle with a short label and constructs", function()
		local bp = UI.Button({ id = "More", label = "...", shape = "circle" })
		expect(bp.props.shape).toBe("circle")
		expect(bp.props.label).toBe("...")
	end)

	it("takes shape = rect explicitly, which is what every Button already was", function()
		expect(UI.Button({ id = "B", label = "Save changes", shape = "rect" }).props.shape).toBe("rect")
	end)

	it("leaves an ordinary Button untouched: no shape prop at all", function()
		expect(UI.Button({ id = "B", label = "Save changes" }).props.shape).toBe(nil)
	end)

	it("takes a semantic icon and keeps a LONG label, because the label is then only the name", function()
		local bp = UI.Button({ id = "More", label = "More actions", shape = "circle", icon = "more" })
		expect(bp.props.icon).toBe("more")
		expect(bp.props.label).toBe("More actions")
	end)

	it("takes a long label on a CONTENT circle for the same reason", function()
		local bp = UI.Button({
			id = "C",
			label = "Open the inventory",
			shape = "circle",
			children = { UI.Text({ id = "Glyph", text = "i" }) },
		})
		expect(bp.props.label).toBe("Open the inventory")
	end)

	it("takes a namespaced icon name a package contributes", function()
		expect(UI.Button({ id = "G", label = "Settings", shape = "circle", icon = "ornate:settings" }).props.icon).toBe(
			"ornate:settings"
		)
	end)

	it("takes ONE authored axis on either side", function()
		expect(UI.Button({ id = "W", label = "x", shape = "circle", width = { type = "fixed", px = 72 } }) ~= nil).toBe(
			true
		)
		expect(UI.Button({ id = "H", label = "x", shape = "circle", height = { type = "fixed", px = 30 } }) ~= nil).toBe(
			true
		)
	end)

	it("takes a BOUND label: a reactive value is checked when it is read, like every reactive prop", function()
		local core = customFactory.new()
		local bp = UI.Button({ id = "N", label = core:signal("1"), shape = "circle" })
		expect(bp.props.label ~= nil).toBe(true)
	end)
end)

describe("circle Button: the reject classes name the field, the rule and the fix", function()
	it("refuses a multi-word drawn label", function()
		local err = fails(function()
			UI.Button({ id = "B", label = "Save changes", shape = "circle" })
		end)
		expect(string.find(err, "UI.Button.label", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "Save changes", 1, true) ~= nil).toBe(true)
		-- the RULE
		expect(string.find(err, "ONE icon or up to 3 characters", 1, true) ~= nil).toBe(true)
		-- the FIX (all three routes out)
		expect(string.find(err, 'icon = "<semantic name>"', 1, true) ~= nil).toBe(true)
		expect(string.find(err, "shorten the label", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "rectangular Button", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a drawn label longer than three characters even without a space", function()
		local err = fails(function()
			UI.Button({ id = "B", label = "MENU", shape = "circle" })
		end)
		expect(string.find(err, "UI.Button.label", 1, true) ~= nil).toBe(true)
	end)

	it("accepts exactly three characters and refuses four", function()
		expect(UI.Button({ id = "A", label = "...", shape = "circle" }) ~= nil).toBe(true)
		expect(UI.Button({ id = "B", label = "99+", shape = "circle" }) ~= nil).toBe(true)
		expect(UI.Button({ id = "C", label = 3, shape = "circle" }) ~= nil).toBe(true)
		fails(function()
			UI.Button({ id = "D", label = "1234", shape = "circle" })
		end)
	end)

	it("refuses BOTH authored axes — that is the arithmetic the solver exists to do", function()
		local err = fails(function()
			UI.Button({
				id = "B",
				label = "x",
				shape = "circle",
				width = { type = "fixed", px = 44 },
				height = { type = "fixed", px = 44 },
			})
		end)
		expect(string.find(err, "at most ONE of", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "1:1", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an icon on a rectangle and points at the control that owns that layout", function()
		local err = fails(function()
			UI.Button({ id = "B", label = "Save", icon = "more" })
		end)
		expect(string.find(err, "UI.Button.icon", 1, true) ~= nil).toBe(true)
		expect(string.find(err, 'shape = "circle"', 1, true) ~= nil).toBe(true)
		expect(string.find(err, "newLabel", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an icon NAME that means nothing, listing the framework vocabulary", function()
		local err = fails(function()
			UI.Button({ id = "B", label = "x", shape = "circle", icon = "hamburger" })
		end)
		expect(string.find(err, "names no semantic icon", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "chevron.trailing", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "ns:name", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an asset id in `icon` — a control never names an asset (ADR-0020 R4)", function()
		fails(function()
			UI.Button({ id = "B", label = "x", shape = "circle", icon = "rbxassetid://123456" })
		end)
	end)

	it("refuses an unknown shape with the closed set", function()
		local err = fails(function()
			UI.Button({ id = "B", label = "x", shape = "pill" })
		end)
		expect(string.find(err, "circle", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a REACTIVE shape: a shape is what the control is, not a state it passes through", function()
		local core = customFactory.new()
		local err = fails(function()
			UI.Button({ id = "B", label = "x", shape = core:signal("circle") })
		end)
		expect(string.find(err, "Signal/Memo", 1, true) ~= nil).toBe(true)
	end)
end)

describe("circle Button: the schema declares it the way the parity checker requires", function()
	it("shape is a closed style-authority set that is not reactive", function()
		local spec = (schema.forClass("Button") :: any).props.shape
		expect(spec.reactive).toBe(false)
		expect(spec.channel).toBe("style")
		expect(table.concat(spec.enum, "|")).toBe("rect|circle")
		expect(authority.authorityFor("Button", "shape")).toBe("style")
	end)

	it("icon is style authority too, and both are creation-applied style props", function()
		expect(authority.authorityFor("Button", "icon")).toBe("style")
		expect(rendererLib.STYLE_PROPS.shape).toBe(true)
		expect(rendererLib.STYLE_PROPS.icon).toBe(true)
	end)

	it("shape is applied FIRST, so every later chrome write sees it", function()
		-- the fallback path's `corner()` reads handle.shape; a shape applied after
		-- a surface would leave a square radius on a disc until something else
		-- touched it. Pinned in the source, because the order IS the contract.
		local order = string.match(rendererSource, "local STYLE_PROP_ORDER: { string } =%s*(%b{})") :: string
		expect(order ~= nil).toBe(true)
		local shapeAt = string.find(order, '"shape"', 1, true) :: number
		local surfaceAt = string.find(order, '"surface"', 1, true) :: number
		local iconAt = string.find(order, '"icon"', 1, true) :: number
		expect(shapeAt < surfaceAt).toBe(true)
		-- ...and the icon LAST: it paints over whatever the chrome settled on
		expect(iconAt > surfaceAt).toBe(true)
	end)
end)

-- ===========================================================================
-- 2. THE SOLVER ENFORCES THE SQUARE
-- ===========================================================================

describe("circle Button geometry: a true 1:1 box from the control metric", function()
	it("with neither axis authored, both come from controls.button.height", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "More", label = "...", shape = "circle" }) },
		}))
		local rect = rectOf(adapter, "/S/More")
		expect(rect.w).toBe(44)
		expect(rect.h).toBe(44)
	end)

	it("the diameter IS the metric: a metric package with a bigger button height makes a bigger disc", function()
		local pkg = packageWith({ controls = { button = { height = 64 } } })
		local metrics = snapshot.resolve(pkg, nil, {})
		expect(metrics.controls.button.height).toBe(64)
		local adapter = render(
			UI.Screen({ id = "S", children = { UI.Button({ id = "More", label = "...", shape = "circle" }) } }),
			metrics
		)
		expect(rectOf(adapter, "/S/More").w).toBe(64)
		expect(rectOf(adapter, "/S/More").h).toBe(64)
	end)

	it("every package answers controls.button.height even when it authored none", function()
		-- the `iconSizes` precedent: resolved in, never declared, so no package's
		-- authored metrics — and therefore no package's content stamp — moves
		local neutral = snapshot.neutral()
		expect(neutral.controls.button.height).toBe(neutral.targetSizes.minimum)
		expect(snapshot.circleDiameter(neutral)).toBe(44)
	end)

	it("a PIXEL package snaps the diameter up onto its grid", function()
		local pkg = packageWith(
			{ controls = { button = { height = 45 } } },
			{ id = "circle-pixel-test", rendering = "pixel", pixelUnit = 8 }
		)
		local metrics = snapshot.resolve(pkg, nil, {})
		expect(metrics.pixelUnit).toBe(8)
		expect(snapshot.circleDiameter(metrics)).toBe(48)
		local adapter = render(
			UI.Screen({ id = "S", children = { UI.Button({ id = "More", label = "...", shape = "circle" }) } }),
			metrics
		)
		expect(rectOf(adapter, "/S/More").w).toBe(48)
		expect(rectOf(adapter, "/S/More").h).toBe(48)
	end)

	it("an authored WIDTH drives the height, and an authored HEIGHT drives the width", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "W", label = "x", shape = "circle", width = { type = "fixed", px = 72 } }),
				UI.Button({ id = "H", label = "x", shape = "circle", height = { type = "fixed", px = 28 } }),
			},
		}))
		expect(rectOf(adapter, "/S/W").w).toBe(72)
		expect(rectOf(adapter, "/S/W").h).toBe(72)
		expect(rectOf(adapter, "/S/H").w).toBe(28)
		expect(rectOf(adapter, "/S/H").h).toBe(28)
	end)

	it("a FILL width still squares: the paired axis takes the extent the parent offered", function()
		-- the `aspect` + `fill` pairing, which measured 0x0 until it was fixed live
		-- on 2026-07-24. The circle rides that vocabulary, so it inherits the fix.
		local adapter = render(
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.HStack({
						id = "Row",
						width = { type = "fixed", px = 120 },
						children = {
							UI.Button({
								id = "Big",
								label = "x",
								shape = "circle",
								width = { type = "fill", weight = 1 },
							}),
						},
					}),
				},
			}),
			nil,
			300,
			300
		)
		local rect = rectOf(adapter, "/S/Row/Big")
		expect(rect.w).toBe(120)
		expect(rect.h).toBe(120)
	end)

	it("a rectangular Button is byte-unchanged: content width, theme button padding", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Save", label = "Save changes" }) },
		}))
		local node = adapter.node("/S/Save")
		expect(node.props.shape).toBe(nil)
		-- the theme's button padding, exactly as before the shape prop existed
		expect(node.props.padding).toBe(snapshot.neutral().controls.button.padding)
	end)

	it("the disc's default padding is ZERO — the diameter IS the box — and an authored one still wins", function()
		local neutral = snapshot.neutral()
		expect(snapshot.buttonPadding(neutral, { shape = "circle" })).toBe(0)
		expect(snapshot.buttonPadding(neutral, {})).toBe(neutral.controls.button.padding)
		expect(snapshot.buttonPadding(neutral, { shape = "circle", padding = 6 })).toBe(6)
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "More", label = "...", shape = "circle" }) },
		}))
		expect(adapter.node("/S/More").props.padding).toBe(0)
	end)
end)

describe("circle Button hit geometry is the FULL SQUARE", function()
	it("a disc at the floor is honestly a 44px target on both axes", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "More", label = "...", shape = "circle" }) },
		}))
		-- the engine rounds PAINT, never the input rect: a UICorner does not carve
		-- the corners out of the hit area, so the target is the square and the 44
		-- floor is measured against it. No expander is needed at the floor.
		expect(rectOf(adapter, "/S/More").w).toBe(44)
		expect(adapter.hitRectOf("/S/More")).toBe(nil)
	end)

	it("a SMALLER disc still gets the 44 floor on both axes, squarely", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Tiny", label = "x", shape = "circle", width = { type = "fixed", px = 28 } }),
			},
		}))
		expect(rectOf(adapter, "/S/Tiny").w).toBe(28)
		local hit = adapter.hitRectOf("/S/Tiny") :: any
		expect(hit ~= nil).toBe(true)
		expect(hit.w).toBe(44)
		expect(hit.h).toBe(44)
	end)
end)

-- ===========================================================================
-- 3. THE PAINT: ONE PILL RULE, ONE HAIRLINE, THROUGH THE RADII MACHINERY
-- ===========================================================================

local function ruleNamed(model: any, name: string): any
	for index, rule in model.rules do
		if rule.name == name then
			return rule, index
		end
	end
	return nil
end

local function neutralSheet(): any
	return sheet_model.build({ themes = { { name = "Dark", style = defaultStyle } } })
end

describe("circle Button paint: the pill and the rim are phantom modifier rules", function()
	it("the base seed emits a 0.5-scale corner on the shape tag — the slider thumb's proven path", function()
		local model = neutralSheet()
		local rule = ruleNamed(model, "Circle button — corner")
		expect(rule ~= nil).toBe(true)
		expect(rule.selector).toBe(`.{CIRCLE_TAG}::UICorner`)
		expect(rule.props.CornerRadius.kind).toBe("udim")
		expect(rule.props.CornerRadius.scale).toBe(0.5)
		expect(rule.props.CornerRadius.offset).toBe(0)
	end)

	it("the rim carries ApplyStrokeMode = Border, or it would halo the glyph instead", function()
		-- director round 10, measured live: UIStroke defaults to Contextual, which
		-- on a TextButton strokes the GLYPHS. Every stroke this compiler emits is
		-- a border hairline and every one of them has to say so.
		local rule = ruleNamed(neutralSheet(), "Circle button — hairline")
		expect(rule ~= nil).toBe(true)
		expect(rule.selector).toBe(`.{CIRCLE_TAG}::UIStroke`)
		expect(rule.props.ApplyStrokeMode.enum).toBe("ApplyStrokeMode")
		expect(rule.props.ApplyStrokeMode.item).toBe("Border")
		expect(rule.props.Color).toBe("$Hairline")
	end)

	it("a PACKAGE emits both in the roles group, after the surfaces whose corners they replace", function()
		local model = sheet_model.buildPackage(packageWith({}))
		local corner = ruleNamed(model, "Circle button — corner")
		local hairline = ruleNamed(model, "Circle button — hairline")
		expect(corner ~= nil).toBe(true)
		expect(hairline ~= nil).toBe(true)
		expect(corner.group).toBe("roles")
		expect(hairline.group).toBe("roles")
	end)

	it("the disc's rim is a METRIC rule prop, so a live hairline edit re-strokes it", function()
		local model = sheet_model.buildPackage(packageWith({}))
		local found = false
		for _, entry in model.metricRuleProps do
			if entry.rule == "Circle button — hairline" then
				expect(entry.path).toBe("strokes.hairline")
				expect(entry.prop).toBe("Thickness")
				found = true
			end
		end
		expect(found).toBe(true)
	end)

	it("a FLAT theme pays ZERO new instances for the disc: rules create the modifiers", function()
		-- the whole point of the phantom path. A package that skins nothing still
		-- gets a circle, and its layer/instance census is untouched by the shape.
		local model = sheet_model.buildPackage(packageWith({}))
		expect(model.census.layers).toBe(0)
		-- NOT zero image rules any more, and the disc is not why: the framework's own icon set (compact-label stage) resolves BELOW a package's map, so a package that declares nothing still DRAWS pictures — and `ImageColor3` is sheet-owned, so each of those names needs its tint rule or the art paints pure white. Found live in the running showcase: Studio Neutral emitted 70 rules and ZERO icon rules while `resolveIcon` returned real art for the same names.
		-- The claim this test makes — the SHAPE costs no instances and no layers —
		-- is unchanged, so it is asserted against the icon floor rather than 0.
		expect(model.census.imageRules).toBe(frameworkIconRuleCount())
	end)
end)

describe("circle Button paint: ONE rule is enough, and that is an invariant, not luck", function()
	-- The cascade is Priority first, then insertion order, with NO selector
	-- specificity — so a rule that sits after every surface corner beats every
	-- surface corner, whichever surface the disc wears. Duplicating the corner
	-- into hover/press/disabled would put five same-named rules in the Style
	-- Editor for a designer's edit to pick between at random (a rule NAME IS
	-- IDENTITY). What makes one rule sufficient is asserted here: this fails the
	-- day some later rule learns to write CornerRadius on a node a disc matches.
	local SURFACE_CORNERS = {
		"Raised panel — corner",
		"Control — corner",
		"Chip — corner",
		"Badge — circle",
		"Primary button — corner",
	}

	local function indexOf(model: any, name: string): number
		local _, index = ruleNamed(model, name)
		expect(index ~= nil).toBe(true)
		return index :: number
	end

	it("beats every surface corner in BOTH builders", function()
		for _, model in { neutralSheet(), sheet_model.buildPackage(packageWith({})) } do
			local circleAt = indexOf(model, "Circle button — corner")
			for _, name in SURFACE_CORNERS do
				expect(circleAt > indexOf(model, name)).toBe(true)
			end
		end
	end)

	it(
		"no LATER rule writes CornerRadius on a selector a circle Button matches — except the skinned suppression",
		function()
			-- the disc's node wears these; anything selecting only on something else
			-- cannot reach it
			local WORN = {
				CIRCLE_TAG,
				sheet_model.TAGS.surfacePrefix .. "control",
				sheet_model.TAGS.surfacePrefix .. "accent",
				sheet_model.TAGS.surfacePrefix .. "chip",
				sheet_model.TAGS.selected,
				sheet_model.TAGS.interactive,
				sheet_model.TAGS.pointerLive,
				"luau-role-destructive",
				"luau-role-cancel",
			}
			local function reachesADisc(selector: string): boolean
				-- a class selector reaches the disc only if EVERY class it names is one
				-- the disc wears; a bare-class selector (TextButton) reaches it too
				for class in string.gmatch(selector, "%.([%w%-]+)") do
					local worn = false
					for _, tag in WORN do
						worn = worn or tag == class
					end
					if not worn then
						return false
					end
				end
				return string.find(selector, ">", 1, true) == nil
			end
			for _, model in { neutralSheet(), sheet_model.buildPackage(packageWith({})) } do
				local circleAt = indexOf(model, "Circle button — corner")
				for index, rule in model.rules do
					if index <= circleAt or rule.props.CornerRadius == nil then
						continue
					end
					if not reachesADisc(rule.selector) then
						continue
					end
					-- the ONE sanctioned exception: once art covers the node the image
					-- IS the silhouette (ADR-0020 R9) and the node's own radius means
					-- nothing, so the skinned-slot suppression must still win
					expect(string.find(rule.name, "Skinned — ", 1, true) == 1).toBe(true)
				end
			end
		end
	)
end)

describe("circle Button paint: the tag reaches the live adapter's desired set", function()
	it("classifyTags earns luau-shape-circle, and rect earns nothing", function()
		expect(sheet_model.classifyTags({ shape = "circle" })[CIRCLE_TAG]).toBe(true)
		expect(sheet_model.classifyTags({ shape = "rect" })[CIRCLE_TAG]).toBe(nil)
		expect(sheet_model.classifyTags({})[CIRCLE_TAG]).toBe(nil)
	end)

	it("the shape composes with every surface, role and state a rectangle takes", function()
		local tags = sheet_model.classifyTags({
			shape = "circle",
			surface = "accent",
			interactive = true,
			pointerLive = true,
			selected = true,
			buttonRole = "destructive",
		})
		expect(tags[CIRCLE_TAG]).toBe(true)
		expect(tags[sheet_model.TAGS.surfacePrefix .. "accent"]).toBe(true)
		expect(tags[sheet_model.TAGS.selected]).toBe(true)
		expect(tags["luau-role-destructive"]).toBe(true)
	end)

	it("the adapter puts the shape in the DESIRED SET, so a later pass cannot square it off", function()
		-- emission ≠ application (the Step 3.5 defect class). syncTags diffs every
		-- luau-* tag against classifyTags' answer; a tag added anywhere else would
		-- survive exactly until the next classification pass.
		local sync = string.match(adapterSource, "local function syncTags%(handle: any%)(.-)local desired = nil")
			or string.match(adapterSource, "local function syncTags%(handle: any%)(.-)\n\tend\n")
		expect(sync ~= nil).toBe(true)
		expect(string.find(sync :: string, "sheet_model.classifyTags", 1, true) ~= nil).toBe(true)
		expect(string.find(sync :: string, "shape = handle.shape", 1, true) ~= nil).toBe(true)
	end)

	it("the adapter records the shape and re-radiuses the REAL UICorner on the fallback path", function()
		local branch =
			string.match(adapterSource, '\t\telseif prop == "shape" then(.-)\t\telseif prop == "icon"') :: string
		expect(branch ~= nil).toBe(true)
		expect(string.find(branch, "handle.shape", 1, true) ~= nil).toBe(true)
		expect(string.find(branch, "syncTags(handle)", 1, true) ~= nil).toBe(true)
		-- the bespoke half: native mode owns the pill through the rule, and the
		-- fallback path owns it through the one real modifier that already exists
		expect(string.find(branch, "cornerRadiusFor(handle, style.radii.control)", 1, true) ~= nil).toBe(true)
		expect(string.find(adapterSource, "UDim.new(0.5, 0)", 1, true) ~= nil).toBe(true)
	end)

	it("every bespoke Button corner site consults the handle, or a disc would go square", function()
		-- `corner()` is called at create (wireInteractiveStates) and again on every
		-- reactive surface change; a call that forgot the handle would re-square a
		-- disc the moment its surface changed.
		for _, call in
			{ "corner(button, style.radii.control, nil, handle)", "corner(instance, style.radii.control, nil, handle)" }
		do
			expect(string.find(adapterSource, call, 1, true) ~= nil).toBe(true)
		end
	end)
end)

-- ===========================================================================
-- 4. THE CONTENT PATHS
-- ===========================================================================

describe("circle Button content: one semantic icon OR up to three characters", function()
	it("an icon button DRAWS the framework's ASCII glyph and keeps the label as the name", function()
		expect(rendererLib.drawnButtonText({ icon = "more", label = "More actions" })).toBe("...")
		expect(rendererLib.drawnButtonText({ icon = "close", label = "Dismiss" })).toBe("x")
		expect(rendererLib.drawnButtonText({ label = "3" })).toBe("3")
	end)

	it("the glyph is what reaches the adapter, not the semantic label", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "More", label = "More actions", shape = "circle", icon = "more" }) },
		}))
		local node = adapter.node("/S/More")
		-- ADR-0020 R4's tofu fix at a public prop: the legible character is in the
		-- tree from the first frame, and NO resolution has to succeed for it to
		-- render. A theme with art for "more" paints the picture over it.
		expect(node.props.label).toBe("...")
		expect(node.props.icon).toBe("more")
	end)

	it("the glyph is also what the SOLVER measured — one decision, two seams", function()
		-- a box reserved for one string and drawn with another is the defect class
		-- this file's siblings have been bitten by repeatedly
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "More", label = "More actions", shape = "circle", icon = "more" }) },
		}))
		-- the disc is exactly the metric: a 12-character label would have measured
		-- far wider if the measure seam had read it
		expect(rectOf(adapter, "/S/More").w).toBe(44)
	end)

	it("a TEXT circle draws its own short label", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "Dots", label = "...", shape = "circle" }) },
		}))
		expect(adapter.node("/S/Dots").props.label).toBe("...")
	end)

	it("the icon request reaches the chrome subsystem through the ONE reconcile entry point", function()
		local branch =
			string.match(adapterSource, '\t\telseif prop == "icon" then(.-)\t\telseif prop == "shadow"') :: string
		expect(branch ~= nil).toBe(true)
		-- the hint may be FROZEN (chrome_slots.attachHint freezes it), so the
		-- branch must COMPOSE a new one rather than write through
		expect(string.find(branch, "handle.decorationHint = merged", 1, true) ~= nil).toBe(true)
		expect(string.find(branch, "syncChrome(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("every framework icon name resolves to an ASCII-safe glyph, so a disc is legible under any font", function()
		for name in themes.ICON_FALLBACK_GLYPHS :: any do
			local glyph = themes.iconGlyph(name)
			expect(glyph ~= nil).toBe(true)
			expect(themes.isSafeGlyph(glyph)).toBe(true)
			expect(#(glyph :: string) <= 3).toBe(true)
		end
	end)
end)

describe("circle Button skinning needs no new slot", function()
	it("a disc classifies to the ordinary `control` decoration slot", function()
		local chrome_slots = require("../src/tokens/chrome_slots")
		-- so a package dresses it with the recipe it already writes — the ornate
		-- stepper plate path — and the v2 slot vocabulary does not grow
		expect(chrome_slots.classify({ class = "Button" })).toBe("control")
		expect(chrome_slots.classify({ class = "Button", surface = "accent" })).toBe("control")
	end)
end)

-- ===========================================================================
-- A WORD IS NEVER BROKEN; A PHRASE IS WRAPPED
-- (director round 13, 2026-07-27: fantasy-parchment's Edit/Done toggle drew
-- "Don" over "e")
--
-- A content-sized button is measured to EXACTLY its label — under three of the
-- reference packages the reserved column and the text came out equal to the
-- pixel — so there is no slack for the engine's own measurement to differ by
-- one, and with wrapping on a one-pixel shortfall does not clip a pixel: it
-- BREAKS THE WORD. The engine does not distinguish a word from a phrase; the
-- framework does, because only one of them has a legal break point.
-- ===========================================================================
describe("a Button's label wraps only where a break is legal", function()
	-- what the adapter was told about ONE button at a fixed width: its box, and the
	-- wrap verdict the renderer carried to it (nil = never written = the adapter's
	-- own default, which is "wrap on whitespace")
	local function drawAt(label: string, px: number): { h: number, textWrapped: any }
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Button({ id = "B", label = label, width = { type = "fixed", px = px } }) },
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		local node = adapter.node("/S/B")
		local out = { h = node.rect.h, textWrapped = node.props.textWrapped }
		root.dispose()
		return out
	end
	local function heightOf(label: string, px: number): number
		return drawAt(label, px).h
	end

	it("one word in a box too small for it stays ONE line — it ellipsizes, never breaks", function()
		-- 130px minus 12+12 padding leaves 106 for a word that needs far more
		local tight = heightOf("Extraordinarily", 130)
		local roomy = heightOf("Extraordinarily", 400)
		expect(tight).toBe(roomy)
	end)

	it("...and the same is true of the short words that showed the defect", function()
		for _, word in { "Edit", "Done" } do
			expect(heightOf(word, 40)).toBe(heightOf(word, 400))
		end
	end)

	it("a PHRASE in a box too small for it still wraps — that break is legal", function()
		-- the theme picker's chips are this case: "Classic Desktop" grows to two
		-- lines on a narrow phone ON PURPOSE (round 9), and clipping it to
		-- "Classic Deskt…" is the regression this asymmetry exists to avoid
		expect(heightOf("Save changes", 130) > heightOf("Save changes", 400)).toBe(true)
	end)

	it("the ADAPTER makes the same call, from the same string AND the solver's width verdict", function()
		-- it rides the label WRITE and not creation because the label is a
		-- reactive binding: the table's own toggle flips Edit <-> Done.
		--
		-- ...AND IT IS NOW AN `and` (director ruling 5, 2026-08-13). The string half
		-- is unchanged; `handle.wraps` is the SOLVER's half, because whether a
		-- phrase's longest word fits needs the drawable width and this seam cannot
		-- see it. Both are ANDed at both write sites, so whichever lands last the
		-- answer is the same one.
		expect(
			string.find(
				adapterSource,
				'instance.TextWrapped = handle.wraps ~= false and string.find(tostring(value), "%s") ~= nil',
				1,
				true
			) ~= nil
		).toBe(true)
		-- the verdict has a WRITE SITE of its own, or the `and` above is gated on a
		-- field nothing ever sets — the shape of a check that cannot fail
		expect(string.find(adapterSource, 'elseif prop == "textWrapped" then', 1, true) ~= nil).toBe(true)
		expect(string.find(rendererSource, "isSingleWord(props.label)", 1, true) ~= nil).toBe(true)
		-- ...and the renderer really carries it across (the seam, by name)
		expect(string.find(rendererSource, 'adapter.setProp(handle, "textWrapped", wraps, "layout")', 1, true) ~= nil).toBe(
			true
		)
	end)

	it("BEHAVIOURAL: the two seams agree on a phrase whose longest word does not fit", function()
		-- the source pin above proves the CALL exists; this proves it lands. A
		-- phrase in a box narrower than its own longest word must arrive at the
		-- adapter with wrapping OFF, or the engine breaks the word inside a box the
		-- solver measured for one line (docs/lessons/one-word-two-subsystems.md).
		local roomy = drawAt("Save changes", 400)
		local tight = drawAt("Save changes", 40)
		expect(`roomy wrapped:{roomy.textWrapped}`).toBe("roomy wrapped:nil")
		expect(`tight wrapped:{tight.textWrapped}`).toBe("tight wrapped:false")
	end)
end)
