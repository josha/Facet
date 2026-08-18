--!strict
-- SEMANTIC ICONS, APPLIED (ADR-0020 R4, rich-skinning-v2 package P4).
--
-- P1 gave the framework `resolveIcon`, the ASCII fallback table and the
-- `iconSizes` validation. Everything asserted here is the OTHER half — the half
-- the Step 3.5 fix round proved a green suite cannot be trusted about:
--
--   1. `iconSizes` rides the SNAPSHOT, so a metric package resizes icons and a
--      control naming a role always resolves a number (P1 deviation 5);
--   2. a CONTROL requests an icon by meaning and draws the framework's ASCII
--      glyph itself — the disclosure caret's geometric shapes and the stepper's
--      U+2212 are gone, which is the tofu defect closed at its source;
--   3. the request reaches the adapter through the internal hint channel;
--   4. the package EMITS a paint rule per resolvable icon and the adapter
--      APPLIES the matching tag, sizes the picture from the snapshot, and turns
--      the glyph underneath off through the desired tag set.
--
-- The source-contract assertions pin ORDER in the live adapter: deleting the
-- application line turns exactly one of these red instead of leaving the suite
-- green and a "+" painted on top of the plate art that replaced it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local fake_target = require("./lib/fake_target")

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")
local frameworkIconRuleCount = require("./lib/framework_icons")

local adapterSource = fs.readFile("src/client/screen_target.luau")
-- the chrome/decoration materializer was extracted to a sibling module when
-- screen_target.luau reached Studio's 200_000-byte Source ceiling. Same
-- anchors, same assertions — only the file they live in moved.
local chromeSource = fs.readFile("src/client/screen_chrome.luau")

local function section(source: string, fromNeedle: string, toNeedle: string): string
	local from = string.find(source, fromNeedle, 1, true)
	expect(from ~= nil).toBe(true)
	local to = string.find(source, toNeedle, from :: number, true)
	expect(to ~= nil).toBe(true)
	return string.sub(source, from :: number, to :: number)
end

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: any = {}
	for k, inner in v do
		out[k] = copy(inner)
	end
	return out
end

local function def(): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "icon-applied-test",
			displayName = "Icon Application Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {
			plus = { content = "rbxassetid://901", preload = "install", fallback = "native", tintRole = "accent" },
			minus = { content = "rbxassetid://902", preload = "install", fallback = "native" },
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local function withIcons(icons: any, extra: ((d: any) -> ())?): any
	local d = def()
	d.icons = icons
	if extra ~= nil then
		extra(d)
	end
	local pkg, report = themes.define(d)
	assert(pkg ~= nil, `the icon fixture must compile: {report.errors[1] and report.errors[1].message or "?"}`)
	return pkg
end

-- ===== 1. iconSizes rides the SNAPSHOT (P1 deviation 5) =====================

describe("iconSizes is metric authority, not a package-only field", function()
	it("every snapshot answers all three roles, authored or not", function()
		local neutral = snapshot.neutral()
		expect(neutral.iconSizes.small).toBe(16)
		expect(neutral.iconSizes.medium).toBe(20)
		expect(neutral.iconSizes.large).toBe(24)
		-- a package that authors NONE of them still resolves all three: a control
		-- that names a role can never get nil back and draw a zero-size picture
		local silent = snapshot.resolve(withIcons({ increment = "plus" }), nil, {})
		expect(silent.iconSizes.medium).toBe(20)
	end)

	it("a METRIC package resizes icons — the whole reason it rides the snapshot", function()
		local big = withIcons({ increment = "plus" }, function(d)
			d.metrics.iconSizes = { small = 24, medium = 40, large = 64 }
		end)
		local snap = snapshot.resolve(big, nil, {})
		expect(snap.iconSizes.small).toBe(24)
		expect(snap.iconSizes.medium).toBe(40)
		expect(snap.iconSizes.large).toBe(64)
	end)

	it("a PARTIAL declaration is filled, never half-broken", function()
		local partial = withIcons({ increment = "plus" }, function(d)
			d.metrics.iconSizes = { large = 48 }
		end)
		local snap = snapshot.resolve(partial, nil, {})
		expect(snap.iconSizes.large).toBe(48)
		expect(snap.iconSizes.small).toBe(16) -- the neutral rung, not nil
		expect(snap.iconSizes.medium).toBe(20)
	end)

	it("the role names are a resolvable metric path on every package", function()
		expect(snapshot.isMetricPath("iconSizes.medium")).toBe(true)
		expect(snapshot.isMetricPath("iconSizes.enormous")).toBe(false)
		expect(snapshot.resolveNumber(snapshot.neutral(), "iconSizes.large")).toBe(24)
	end)

	it("adding it moved NO package's content stamp", function()
		-- the failure this guards: declaring iconSizes in the neutral package
		-- definition (rather than filling it at resolve) re-stamped every derived
		-- package, which would have invalidated the stored Step 3.5 captures
		local base = snapshot.neutralPackage()
		expect(base.metrics.iconSizes).toBeNil()
	end)
end)

-- ===== 2. the CONTROL draws an ASCII glyph and requests a meaning ===========

describe("the tofu defect, closed at its source", function()
	local disclosureSource = fs.readFile("src/controls/disclosure_group.luau")
	local stepperSource = fs.readFile("src/controls/stepper.luau")

	local function isAscii(s: string): boolean
		for i = 1, #s do
			local byte = string.byte(s, i)
			if byte :: number > 126 then
				return false
			end
		end
		return true
	end

	it("the disclosure caret's geometric shapes are GONE from the source", function()
		-- U+25BE / U+25B8: present in some faces, absent in Michroma, which is
		-- exactly how the sci-fi follow-ups caret shipped as tofu
		expect(string.find(disclosureSource, "\u{25BE}", 1, true)).toBeNil()
		expect(string.find(disclosureSource, "\u{25B8}", 1, true)).toBeNil()
		expect(string.find(disclosureSource, 'themePackage.iconGlyph("chevron.down")', 1, true) ~= nil).toBe(true)
		expect(string.find(disclosureSource, 'themePackage.iconGlyph("chevron.trailing")', 1, true) ~= nil).toBe(true)
		-- ...and the caret REQUESTS the icon, exactly as the stepper's glyphs do
		-- (phase-gate verifier F3: the glyph half shipped, the request half did
		-- not, so every reference package's caret art was a dead declaration)
		expect(string.find(disclosureSource, 'caret("chevron.down", CARET_OPEN)', 1, true) ~= nil).toBe(true)
		expect(string.find(disclosureSource, 'caret("chevron.trailing", CARET_SHUT)', 1, true) ~= nil).toBe(true)
		expect(string.find(disclosureSource, "chrome_slots.attachHint", 1, true) ~= nil).toBe(true)
	end)

	it("the stepper's U+2212 minus sign is gone and both glyphs are icon requests", function()
		expect(string.find(stepperSource, "\u{2212}", 1, true)).toBeNil()
		expect(string.find(stepperSource, 'themePackage.iconGlyph("decrement")', 1, true) ~= nil).toBe(true)
		expect(string.find(stepperSource, 'themePackage.iconGlyph("increment")', 1, true) ~= nil).toBe(true)
		expect(string.find(stepperSource, 'icon = "decrement"', 1, true) ~= nil).toBe(true)
		expect(string.find(stepperSource, 'icon = "increment"', 1, true) ~= nil).toBe(true)
	end)

	it("the glyphs a control actually renders are plain ASCII", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local expanded = core:signal(false)
		local group = Facet.Controls.DisclosureGroup(core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return UI.VStack({ id = "Body", children = {} })
			end,
		})
		local header = group.blueprint.children[1]
		-- the header is a CONTENT button now: `label` stays the semantic label and
		-- the caret is its own node, so suppressing the caret's glyph under a
		-- theme's picture cannot take the label with it
		expect(header.props.label).toBe("Advanced")
		expect(isAscii(header.props.label)).toBe(true)
		local caretShut = header.children[2].props.thenView()
		expect(caretShut.props.text).toBe(">")
		expect(isAscii(caretShut.props.text)).toBe(true)
		local caretOpen = header.children[1].props.thenView()
		expect(caretOpen.props.text).toBe("v")
		expect(isAscii(caretOpen.props.text)).toBe(true)
		group.dispose()
	end)

	-- phase-gate verifier F3. THE HEADER PUBLISHES THE REQUEST: without this the
	-- reference packages' `chevron.down` / `chevron.trailing` art could never
	-- paint, and rs-a7 read "the glyph is still showing" as a success under a
	-- chevron-DECLARING package.
	it("the disclosure header PUBLISHES the chevron icon request, both ways", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		local expanded = core:signal(false)
		local group = Facet.Controls.DisclosureGroup(core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return UI.VStack({ id = "Body", children = {} })
			end,
		})
		pres.present(UI.Screen({ id = "S", children = { group.blueprint } }))
		pres.refresh()
		-- collapsed: the trailing chevron, on a node that draws the ASCII glyph
		local shut = adapter.node("/S/Adv/Header/CaretShut/then/Caret")
		expect(shut ~= nil).toBe(true)
		expect(shut.decorationHint.icon).toBe("chevron.trailing")
		expect(shut.props.text).toBe(">")
		expect(adapter.node("/S/Adv/Header/CaretOpen/then/Caret")).toBeNil()
		-- ...and the LABEL is a separate node, so the icon's glyph suppression
		-- (adapter TextTransparency / the `luau-icon-art` tag) cannot reach it
		expect(adapter.node("/S/Adv/Header/Label").props.text).toBe("Advanced")
		-- expanded: the down chevron, and exactly one caret is mounted at a time
		expanded:set(true)
		pres.refresh()
		local open = adapter.node("/S/Adv/Header/CaretOpen/then/Caret")
		expect(open ~= nil).toBe(true)
		expect(open.decorationHint.icon).toBe("chevron.down")
		expect(open.props.text).toBe("v")
		expect(adapter.node("/S/Adv/Header/CaretShut/then/Caret")).toBeNil()
		-- both names are ones a package can actually declare art for
		expect(themes.ICON_FALLBACK_GLYPHS["chevron.down"] ~= nil).toBe(true)
		expect(themes.ICON_FALLBACK_GLYPHS["chevron.trailing"] ~= nil).toBe(true)
		group.dispose()
	end)

	it("every framework glyph a control can request is ASCII by construction", function()
		for name in themes.ICON_FALLBACK_GLYPHS :: any do
			local glyph = themes.iconGlyph(name)
			expect(glyph ~= nil).toBe(true)
			expect(themes.isSafeGlyph(glyph)).toBe(true)
		end
		expect(themes.iconGlyph("not.an.icon")).toBeNil()
	end)
end)

-- ===== 3. the request REACHES the adapter ==================================

describe("the icon request travels the internal hint channel", function()
	local function mountStepper()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local control = Facet.Controls.Stepper(core, {
			id = "Qty",
			label = "Qty",
			value = core:signal(3),
			min = 0,
			max = 10,
		})
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		return adapter
	end

	it("blueprint -> mount -> renderer -> adapter.create carries slot AND icon", function()
		local adapter = mountStepper()
		local inc = adapter.node("/S/Qty/Inc")
		local dec = adapter.node("/S/Qty/Dec")
		expect(inc.decorationHint.slot).toBe("stepperPlate")
		expect(inc.decorationHint.icon).toBe("increment")
		expect(dec.decorationHint.icon).toBe("decrement")
		-- ...and the node's own text is STILL the legible character, so a theme
		-- with no icon map needs nothing to happen at all
		expect(inc.props.label).toBe("+")
		expect(dec.props.label).toBe("-")
	end)

	it("attachHint rejects an asset id where a meaning belongs", function()
		local ok = pcall(function()
			chrome_slots.attachHint(UI.Box({ id = "B" }), { icon = "" })
		end)
		expect(ok).toBe(false)
	end)
end)

-- ===== 4. EMISSION and APPLICATION, paired =================================

describe("icon paint: the package emits, the adapter applies", function()
	it("a resolvable, tinted icon emits exactly one rule on its own tag", function()
		local pkg = withIcons({ increment = "plus", decrement = "minus" })
		local model = sheet_model.buildPackage(pkg)
		local byName: { [string]: any } = {}
		for _, rule in model.rules do
			byName[rule.name] = rule
		end
		-- `plus` declares tintRole = "accent"; `minus` declares none, so it has
		-- nothing for a rule to own and gets none (an empty rule is a lie)
		expect(byName["Icon — increment"] ~= nil).toBe(true)
		expect(byName["Icon — decrement"]).toBeNil()
		expect(byName["Icon — increment"].selector).toBe(".luau-chrome-icon-increment")
		expect(byName["Icon — increment"].props.ImageColor3).toBe("$Accent")
	end)

	it("the tag SANITIZES the semantic name, because dots are selector syntax", function()
		expect(chrome_slots.iconTagFor("chevron.trailing")).toBe("luau-chrome-icon-chevron-trailing")
		expect(chrome_slots.iconTagFor("gauge:needle.up")).toBe("luau-chrome-icon-gauge--needle-up")
		-- and it carries the chrome prefix, which is what earns the rule the
		-- image-property allowance in the compiler
		expect(string.find(chrome_slots.iconTagFor("close"), chrome_slots.TAGS.slotPrefix, 1, true)).toBe(1)
	end)

	it("a rule with a dotted icon name compiles and selects one class", function()
		local pkg = withIcons({ ["chevron.trailing"] = "plus" })
		local model = sheet_model.buildPackage(pkg)
		local found = false
		for _, rule in model.rules do
			if rule.name == "Icon — chevron.trailing" then
				found = true
				expect(rule.selector).toBe(".luau-chrome-icon-chevron-trailing")
			end
		end
		expect(found).toBe(true)
	end)

	it("a PIXEL package stamps Pixelated on the icon rule too, and counts it", function()
		local d = def()
		d.identity.rendering = "pixel"
		d.identity.pixelUnit = 4
		d.icons = { increment = "plus", decrement = "minus" }
		local pkg = themes.define(d)
		assert(pkg ~= nil, "the pixel icon fixture must compile")
		local model = sheet_model.buildPackage(pkg)
		local rules = 0
		for _, rule in model.rules do
			if string.find(rule.name, "Icon", 1, true) == 1 then
				rules += 1
				expect(rule.props.ResampleMode.item).toBe("Pixelated")
			end
		end
		-- BOTH icons now have something to own: the untinted one earns a rule purely
		-- for the pixel stamp — and every framework name this fixture does NOT
		-- declare earns one too, because the framework's own icon set (compact-label stage) resolves BELOW a package's map, so a package that declares nothing still DRAWS pictures — and `ImageColor3` is sheet-owned, so each of those names needs its tint rule or the art paints pure white. Found live in the running showcase: Studio Neutral emitted 70 rules and ZERO icon rules while `resolveIcon` returned real art for the same names.
		-- every name that RESOLVES to art earns exactly one rule, whether the art is
		-- this package's or the framework's — the two it declares are framework
		-- names it overrode, not extra rules on top
		expect(rules).toBe(frameworkIconRuleCount())
		expect(model.census.pixelatedRules).toBe(model.census.imageRules)
	end)

	it("the glyph suppression is a TAG, because TextTransparency is sheet-owned", function()
		local tags = sheet_model.classifyTags({ surface = "control", interactive = true, iconArt = true })
		expect(tags[chrome_slots.TAGS.iconArt]).toBe(true)
		local without = sheet_model.classifyTags({ surface = "control", interactive = true })
		expect(without[chrome_slots.TAGS.iconArt]).toBeNil()
		-- ...and every package emits the rule that tag selects, including one
		-- with no icons at all: a swap must not change whether it exists
		local model = sheet_model.buildPackage(withIcons({ increment = "plus" }))
		local plain = sheet_model.buildPackage((themes.define(def())))
		for _, built in { model, plain } do
			local found = false
			for _, rule in built.rules do
				if rule.name == "Semantic icon replaces the glyph" then
					found = true
					expect(rule.selector).toBe(".luau-icon-art")
					expect(rule.props.TextTransparency.value).toBe(1)
				end
			end
			expect(found).toBe(true)
		end
	end)

	it("the suppression rule is LAST in the cascade, so it beats the disabled value", function()
		local model = sheet_model.buildPackage(withIcons({ increment = "plus" }))
		local iconIndex, disabledIndex = 0, 0
		for index, rule in model.rules do
			if rule.name == "Semantic icon replaces the glyph" then
				iconIndex = index
			elseif rule.name == "Disabled button" then
				disabledIndex = index
			end
		end
		expect(disabledIndex > 0).toBe(true)
		expect(iconIndex > disabledIndex).toBe(true)
	end)

	it("the ADAPTER resolves through the one ruling and applies all four halves", function()
		local apply = section(chromeSource, "local function syncIconArt(handle: any)", "\n\tend")
		-- resolution is the PURE function, never a second lookup
		expect(string.find(apply, "themePackage.resolveIcon(package, name)", 1, true) ~= nil).toBe(true)
		-- a glyph answer creates nothing
		expect(string.find(apply, 'resolved.source ~= "asset"', 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "destroyIconArt(handle)", 1, true) ~= nil).toBe(true)
		-- size comes from the SNAPSHOT's iconSizes
		expect(string.find(apply, "snap.iconSizes[role]", 1, true) ~= nil).toBe(true)
		-- the tag the emitted rule selects on
		expect(string.find(apply, "chrome_slots.iconTagFor(name)", 1, true) ~= nil).toBe(true)
		-- the picture is input-transparent and above the whole ladder
		expect(string.find(apply, "child.Active = false", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "chrome_slots.ICON_Z_INDEX", 1, true) ~= nil).toBe(true)
		-- ...and the glyph goes off through the DESIRED SET, not a stray tag
		expect(string.find(apply, "handle.iconArt = true", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "syncTags(handle)", 1, true) ~= nil).toBe(true)
		local classify = section(adapterSource, "local function syncTags(handle: any)", "\n\tend")
		expect(string.find(classify, "iconArt = handle.iconArt == true", 1, true) ~= nil).toBe(true)
	end)

	it("native mode writes NO sheet-owned paint on the picture (rs-m2's defeat rule)", function()
		local apply = section(chromeSource, "local function syncIconArt(handle: any)", "\n\tend")
		local guard: any = string.find(apply, "if not nativeMode then", 1, true)
		expect(guard ~= nil).toBe(true)
		-- both paint properties sit BEHIND the fallback guard; only Image, Size
		-- and the tag are unconditional
		local tintAt: any = string.find(apply, "child.ImageColor3", 1, true)
		local resampleAt: any = string.find(apply, "child.ResampleMode", 1, true)
		local imageAt: any = string.find(apply, "child.Image = resolved.contentId", 1, true)
		expect(tintAt > guard).toBe(true)
		expect(resampleAt > guard).toBe(true)
		expect(imageAt < guard).toBe(true)
	end)

	it("the lift dies with the glyph, or the character reappears ABOVE the art", function()
		local lift = section(chromeSource, "local function syncChromeText(handle: any, deco:", "\n\t\tlocal instance")
		expect(string.find(lift, "handle.iconArt == true", 1, true) ~= nil).toBe(true)
		expect(string.find(lift, "destroyChromeText(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("syncChrome runs the icon seam AHEAD of every early return", function()
		local sync = section(chromeSource, "function syncChromeInner(handle: any)", "\n\tend\n")
		local iconAt: any = string.find(sync, "syncIconArt(handle)", 1, true)
		expect(iconAt ~= nil).toBe(true)
		-- the bar-fill, layer-ladder and native-recipe branches all RETURN; a
		-- hinted node with no recipe for its slot must never reach one of them
		-- before its icon has landed (the "a tag whose application depends on
		-- another package feature is not applied at all" lesson)
		for _, branch in { 'elseif slot == "barFill" then', "if stack ~= nil then", "if plan == nil then" } do
			local branchAt: any = string.find(sync, branch, 1, true)
			expect(branchAt ~= nil).toBe(true)
			expect(iconAt < branchAt).toBe(true)
		end
	end)

	it("the picture and its census FALL with the node", function()
		local remove = section(adapterSource, "function adapter.remove(handle: any)", "\n\tend")
		expect(string.find(remove, "destroyIconArt(handle)", 1, true) ~= nil).toBe(true)
		local destroyRoot = section(adapterSource, "function adapter.destroyRoot(rootHandle: any)", "\n\tend")
		expect(string.find(destroyRoot, "destroyIconArt(handle)", 1, true) ~= nil).toBe(true)
		local census = section(adapterSource, "function adapter.chromeCensus(): any", "\n\tend")
		expect(string.find(census, "census.iconArt = actualIcons", 1, true) ~= nil).toBe(true)
		expect(string.find(census, "census.iconRequests = iconRequests", 1, true) ~= nil).toBe(true)
	end)

	it("the SNAPSHOT reaches the adapter inside the swap transaction", function()
		local controller = fs.readFile("src/client/theme_controller.luau")
		expect(
			string.find(controller, "pcall(adapter.setThemePackage, activePackage, themeName, next_)", 1, true) ~= nil
		).toBe(true)
		local set = section(adapterSource, "function adapter.setThemePackage(package: any?", "\n\tend")
		-- a package that differs ONLY in its icon ladder still re-syncs, or a
		-- metric-only icon change would paint at the previous package's size
		expect(string.find(set, "activeThemeSnapshot = snapshot", 1, true) ~= nil).toBe(true)
		expect(string.find(set, "if changed or sizesChanged then", 1, true) ~= nil).toBe(true)
		-- ...and a package-ONLY call (the decoration surface's historic shape)
		-- keeps the metrics it has rather than resizing every icon to the
		-- neutral rung for a frame
		expect(string.find(set, "if snapshot ~= nil or package == nil then", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 5. property authority over this stage's image paint (fix round) ======
--
-- platform verifier F4 + architecture verifier F4. `assertBespokePaint` is the
-- central gate that makes a missed `if not nativeMode` guard LOUD instead of a
-- silent permanent rule defeat — but its manifest listed no image property at
-- all, so this whole stage's visual surface (every skinned slot, layer, bar part,
-- toggle part and icon) sat outside it. And the manifest's "the ONLY sanctioned
-- exceptions" comment named two instance families while v2 shipped eight more.

describe("image paint is declared sheet-owned, with the adapter's instances named", function()
	local authority = require("../src/render/authority")

	it("all eight image properties are native-sheet-owned", function()
		for _, prop in
			{
				"Image",
				"ImageColor3",
				"ImageTransparency",
				"ScaleType",
				"SliceCenter",
				"SliceScale",
				"TileSize",
				"ResampleMode",
			}
		do
			expect(authority.nativeSheetOwned(prop)).toBe(true)
		end
	end)

	it("the sanctioned Image exception is REAL: no emitted Icon rule carries Image", function()
		-- the exception exists because no rule can pick a content id per node.
		-- It is only sanctioned while no rule tries: a package that emitted
		-- `Image` on an icon tag would have the adapter's write defeat it
		-- permanently and silently.
		local pkg = withIcons({
			["chevron.down"] = "plus",
			["chevron.trailing"] = "plus",
			["increment"] = "plus",
			["decrement"] = "minus",
		})
		local pixelPkg = withIcons({ ["chevron.down"] = "plus", ["increment"] = "minus" }, function(d)
			d.identity.rendering = "pixel"
			d.identity.pixelUnit = 4
		end)
		for _, model in { sheet_model.buildPackage(pkg), sheet_model.buildPackage(pixelPkg) } do
			local seen = 0
			for _, rule in model.rules do
				if string.sub(rule.name, 1, #"Icon — ") == "Icon — " then
					seen += 1
					expect(rule.props.Image).toBeNil()
					expect(rule.props.ImageContent).toBeNil()
				end
			end
			expect(seen > 0).toBe(true)
		end
	end)

	it("every adapter-owned instance family is declared, and the names come from chrome_slots", function()
		local declared = authority.bespokeInstances()
		local names = {
			-- the two families that are NOT chrome (ADR-0022): a presentation UIScale
			-- and the authored UI.stroke border. Their names live in the manifest
			-- itself rather than in chrome_slots, and the invariant is the same one —
			-- the adapter reads the name from a shared constant, so a rename cannot
			-- leave the manifest and the instance disagreeing.
			authority.INSTANCE_NAMES.motionScale,
			authority.INSTANCE_NAMES.stroke,
			chrome_slots.DECORATION_NAME,
			chrome_slots.TEXT_LIFT_NAME,
			chrome_slots.LAYER_NAME_PREFIX,
			chrome_slots.ICON_NAME,
			chrome_slots.BAR_WINDOW_NAME,
			chrome_slots.BAR_FILL_NAME,
			chrome_slots.BAR_CENTER_NAME,
			chrome_slots.BAR_CAP_NAMES.start,
			chrome_slots.BAR_CAP_NAMES.finish,
			chrome_slots.TOGGLE_PARTS.toggleTrack,
			chrome_slots.TOGGLE_PARTS.toggleKnob,
		}
		for _, name in names do
			expect(declared[name] ~= nil).toBe(true)
		end
		-- frozen the other way too: nothing is declared that no constant names
		local known: { [string]: boolean } = {}
		for _, name in names do
			known[name] = true
		end
		for name in declared do
			expect(known[name]).toBe(true)
		end
	end)

	it("the icon picture is TAGGED BEFORE IT IS PARENTED, like every other create path", function()
		local sync = section(chromeSource, "local function syncIconArt(handle: any", "\n\tend")
		local addTag = string.find(sync, "CollectionService:AddTag(child, tag)", 1, true)
		local parent = string.find(sync, "child.Parent = handle.instance", 1, true)
		expect(addTag ~= nil and parent ~= nil).toBe(true)
		expect((addTag :: number) < (parent :: number)).toBe(true)
	end)
end)
