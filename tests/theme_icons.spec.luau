--!strict
-- SEMANTIC ICON ASSETS (rich-skinning-v2 package P1).
--
-- Controls request an icon by MEANING; a raw asset id in control code stays
-- forbidden. The propositions:
--
--   1. the icon map and the `iconSizes` metric roles validate like every other
--      section: unknown names and unknown roles are compile errors that name the
--      legal set;
--   2. the framework owns a fallback GLYPH per semantic name, and every one of
--      them is plain ASCII — the sci-fi follow-ups caret was a PRIVATE-USE
--      codepoint, which is how tofu shipped and why no test caught it;
--   3. resolution is a pure function with three honest answers: the theme's art,
--      the framework's glyph, or nothing at all for a name that means nothing.

local t = require("./lib/testkit")
local fs = require("@lune/fs")
local describe, it, expect = t.describe, t.it, t.expect

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local chrome_slots = require("../src/tokens/chrome_slots")

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
			id = "icon-test",
			displayName = "Icon Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {
			caret = { content = "rbxassetid://31", preload = "install", fallback = "native", tintRole = "accent" },
			caretHot = { content = "rbxassetid://32", preload = "install", fallback = "native" },
			cross = { content = "rbxassetid://33", preload = "lazy", fallback = "native" },
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local function withIcons(icons: any, iconSizes: any?): any
	local d = def()
	d.icons = icons
	if iconSizes ~= nil then
		d.metrics.iconSizes = iconSizes
	end
	return d
end

local function firstOfField(report: any, field: string): any
	for _, entry in report.errors do
		if entry.field == field then
			return entry
		end
	end
	return nil
end

describe("themes.define: the icon map is validated like every other section", function()
	it("compiles a map of semantic names, variants included", function()
		local pkg, report = themes.define(withIcons({
			["chevron.trailing"] = "caret",
			["close"] = { default = "cross", hover = "caretHot" },
		}, { small = 12, medium = 16, large = 24 }))
		expect(report.ok).toBe(true)
		expect(pkg.icons["chevron.trailing"]).toBe("caret")
		expect(pkg.metrics.iconSizes.medium).toBe(16)
	end)

	it("a package with no icons carries no icons section, and stamps as it always did", function()
		local plain = themes.define(def())
		expect(plain.icons).toBeNil()
		-- adding icons MOVES the stamp (they are package content), and a package
		-- without them is untouched by the section existing at all
		local iconed = themes.define(withIcons({ ["close"] = "cross" }))
		expect(iconed.stamp).never().toBe(plain.stamp)
		expect(themes.define(def()).stamp).toBe(plain.stamp)
	end)

	it("rejects a name that is neither a framework icon nor namespaced", function()
		local _, report = themes.define(withIcons({ ["chevron.trailling"] = "caret" }))
		expect(report.ok).toBe(false)
		local entry = firstOfField(report, "icons.chevron.trailling")
		expect(entry ~= nil).toBe(true)
		expect(string.find(entry.fix, "chevron.trailing", 1, true) ~= nil).toBe(true)
	end)

	it("accepts a namespaced name, which is how a custom control contributes one", function()
		local pkg, report = themes.define(withIcons({ ["demo:gauge.needle"] = "caret" }))
		expect(report.ok).toBe(true)
		expect(pkg.icons["demo:gauge.needle"]).toBe("caret")
	end)

	it("rejects art the package never declared, and a malformed reference", function()
		local _, missing = themes.define(withIcons({ ["close"] = "ghost" }))
		expect(missing.ok).toBe(false)
		expect(firstOfField(missing, "icons.close") ~= nil).toBe(true)
		local _, malformed = themes.define(withIcons({ ["close"] = { hover = "cross" } }))
		expect(malformed.ok).toBe(false)
	end)

	-- architecture verifier F6. `resolveIcon` re-normalized the authored map on
	-- EVERY call and, when the entry did not normalize, fell silently through to
	-- the fallback glyph — so a malformed icon would have rendered as "this theme
	-- declares no art" rather than as a compile error. That fall-through is only
	-- safe if `define` is the wall; this pins that it is, and that resolution now
	-- reads a compiled sibling instead of re-deriving one.
	it("define is the ONLY icon wall: a map with no `default` is a compile error", function()
		local _, report = themes.define(withIcons({ ["checkmark"] = { hover = "caretHot" } }))
		expect(report.ok).toBe(false)
		local entry = firstOfField(report, "icons.checkmark")
		expect(entry ~= nil).toBe(true)
		-- a state naming art the package never declared is the other wall
		local _, ghost = themes.define(withIcons({ ["checkmark"] = { default = "cross", hover = "ghost" } }))
		expect(ghost.ok).toBe(false)
		expect(firstOfField(ghost, "icons.checkmark") ~= nil).toBe(true)
	end)

	it("resolveIcon is a LOOKUP: the compiled sibling carries the resolved art", function()
		local pkg = themes.define(withIcons({
			["chevron.trailing"] = "caret",
			["close"] = { default = "cross", hover = "caretHot" },
		}))
		-- the authored field is untouched (exported data and stamps do not move)
		expect(pkg.icons["chevron.trailing"]).toBe("caret")
		-- ...and a resolved sibling sits beside it, one entry per declared state
		expect(pkg.iconArt.close.default.assetName).toBe("cross")
		expect(pkg.iconArt.close.hover.assetName).toBe("caretHot")
		expect(pkg.iconArt.close.pressed).toBeNil()
		local hover = themes.resolveIcon(pkg, "close", "hover")
		expect(hover.source).toBe("asset")
		expect(hover.state).toBe("hover")
		expect(hover.contentId).toBe(pkg.assets.caretHot.contentId)
		-- an unstated state falls back to `default`, as slot art does
		expect(themes.resolveIcon(pkg, "close", "pressed").state).toBe("default")
		-- a name this package has no art for falls to the FRAMEWORK's own art
		-- (compact-label stage: package art -> framework art -> ASCII glyph), and
		-- an unknown name is still nil at every rung
		expect(themes.resolveIcon(pkg, "menu").source).toBe("asset")
		expect(themes.resolveIcon(pkg, "not.a.name")).toBeNil()
		-- the normalizer is GONE from the resolution path
		local src = fs.readFile("src/themes/package.luau")
		local from = string.find(src, "function package.resolveIcon(", 1, true) :: number
		local body = string.sub(src, from, string.find(src, "\nend", from, true) :: number)
		expect(string.find(body, "normalizeVariant", 1, true)).toBeNil()
		expect(string.find(body, "variantAsset", 1, true)).toBeNil()
	end)

	it("rejects an unknown iconSizes role and a non-positive size", function()
		local _, unknown = themes.define(withIcons({ ["close"] = "cross" }, { huge = 64 }))
		expect(unknown.ok).toBe(false)
		expect(firstOfField(unknown, "metrics.iconSizes.huge") ~= nil).toBe(true)
		local _, zero = themes.define(withIcons({ ["close"] = "cross" }, { small = 0 }))
		expect(zero.ok).toBe(false)
	end)

	it("icon art joins the preload seam by its own policy", function()
		local pkg = themes.define(withIcons({
			["chevron.trailing"] = "caret",
			["close"] = { default = "cross", hover = "caretHot" },
		}))
		local install: { [string]: boolean } = {}
		for _, entry in chrome_slots.assetsToPreload(pkg, "install") do
			install[entry.name] = true
		end
		expect(install.caret).toBe(true)
		expect(install.caretHot).toBe(true)
		expect(install.cross).toBeNil() -- declared lazy
	end)
end)

describe("the fallback glyph table can never be tofu", function()
	it("every glyph is plain ASCII, and the check that says so can fail", function()
		local count = 0
		for name, glyph in themes.ICON_FALLBACK_GLYPHS :: any do
			count += 1
			expect(themes.isSafeGlyph(glyph)).toBe(true)
			-- byte-level, so the assertion is about the STRING and not about a
			-- helper agreeing with itself
			for i = 1, #glyph do
				expect(string.byte(glyph, i) < 128).toBe(true)
			end
			expect(themes.isIconName(name)).toBe(true)
		end
		expect(count >= 8).toBe(true)
	end)

	it("a private-use codepoint FAILS the check — the sci-fi caret defect", function()
		-- U+E000 is the start of the Basic Multilingual Plane's private use
		-- area: nothing in the font has it, the engine draws tofu, and no test
		-- could see it
		expect(themes.isSafeGlyph("\u{E000}")).toBe(false)
		expect(themes.isSafeGlyph("\u{F8FF}")).toBe(false)
		-- ...and so do the geometric shapes, which are the same hazard milder:
		-- present in some faces, missing in others
		expect(themes.isSafeGlyph("▸")).toBe(false)
		expect(themes.isSafeGlyph("▾")).toBe(false)
		expect(themes.isSafeGlyph("")).toBe(false)
		expect(themes.isSafeGlyph(nil)).toBe(false)
	end)
end)

-- P1d (2026-09-18): a SMALL common set for the next controls (Notice/Badge/
-- Snackbar, DateTimePicker, Vote, Avatar, Pagination) — pinned by exact name,
-- floor and asset, the way the shipped rows above already are.
describe("P1d: eleven common glyphs (status, calendar, clock, vote, person, chevron ends)", function()
	local FLOORS: { [string]: string } = {
		["status.info"] = "i",
		["status.success"] = "ok",
		["status.warning"] = "!",
		["status.error"] = "x!",
		["calendar"] = "[#]",
		["clock"] = "(:)",
		["vote.up"] = "+1",
		["vote.down"] = "-1",
		["person"] = "@",
		["chevron.first"] = "|<",
		["chevron.last"] = ">|",
	}
	local ASSET_NAMES: { [string]: string } = {
		["status.info"] = "facet_icon_info",
		["status.success"] = "facet_icon_success",
		["status.warning"] = "facet_icon_warning",
		["status.error"] = "facet_icon_error",
		["calendar"] = "facet_icon_calendar",
		["clock"] = "facet_icon_clock",
		["vote.up"] = "facet_icon_thumb_up",
		["vote.down"] = "facet_icon_thumb_down",
		["person"] = "facet_icon_person",
		["chevron.first"] = "facet_icon_chevron_first",
		["chevron.last"] = "facet_icon_chevron_last",
	}

	it("each name carries its exact ASCII floor and an ART row for the matching asset", function()
		local standard_icons = require("../src/themes/standard_icons")
		for name, floor in FLOORS do
			expect(themes.ICON_FALLBACK_GLYPHS[name]).toBe(floor)
			expect(themes.isSafeGlyph(floor)).toBe(true)
			expect(themes.isIconName(name)).toBe(true)
			local entry = (standard_icons.ART :: any)[name]
			expect(entry ~= nil).toBe(true)
			expect(entry.assetName).toBe(ASSET_NAMES[name])
			expect(entry.tintRole).toBe("content")
			-- Every shipped row resolves to its exact art, even without a package.
			expect(themes.resolveIcon(nil, name).source).toBe("asset")
			expect(themes.resolveIcon(nil, name).contentId).toBe(entry.contentId)
			expect(themes.resolveIcon(snapshot.neutralPackage(), name).source).toBe("asset")
			expect(themes.resolveIcon(snapshot.neutralPackage(), name).contentId).toBe(entry.contentId)
		end
		expect(standard_icons.ART["status.success"].contentId).toBe(standard_icons.ART.checkmark.contentId)
		expect(fs.readFile("assets/icons/facet_icon_success.png") == fs.readFile("assets/icons/facet_icon_check.png")).toBe(
			true
		)
	end)
end)

describe("settings gear", function()
	it("resolves the archived asset and retains an ASCII fallback", function()
		expect(themes.ICON_FALLBACK_GLYPHS.settings).toBe("*")
		for _, pkg in { false, snapshot.neutralPackage() } do
			local answer = themes.resolveIcon(if pkg == false then nil else pkg, "settings")
			expect(answer.source).toBe("asset")
			expect(answer.contentId).toBe("rbxassetid://78513807849201")
			expect(answer.tintRole).toBe("content")
		end
	end)
end)

describe("themes.resolveIcon: three honest answers", function()
	it("the theme's art when it has some, per state", function()
		local pkg = themes.define(withIcons({
			["chevron.trailing"] = "caret",
			["close"] = { default = "cross", hover = "caretHot" },
		}))
		local resolved = themes.resolveIcon(pkg, "chevron.trailing")
		expect(resolved.source).toBe("asset")
		expect(resolved.contentId).toBe(pkg.assets.caret.contentId)
		-- the tint role rides the existing asset field, so an icon retints with
		-- the palette instead of shipping a colour per theme
		expect(resolved.tintRole).toBe("accent")
		expect(themes.resolveIcon(pkg, "close", "hover").contentId).toBe(pkg.assets.caretHot.contentId)
		-- an unstated state falls back to default, exactly as slot art does
		local defaulted = themes.resolveIcon(pkg, "close", "pressed")
		expect(defaulted.contentId).toBe(pkg.assets.cross.contentId)
		expect(defaulted.state).toBe("default")
	end)

	it("the FRAMEWORK's own art when the theme declares none", function()
		-- the middle rung, added by the compact-label stage. "This package ships
		-- no icon for that name" used to mean "draw the framework's character"; it
		-- now means "draw the framework's picture", and the character is the floor
		-- beneath THAT.
		local flat = snapshot.neutralPackage()
		local resolved = themes.resolveIcon(flat, "chevron.trailing")
		expect(resolved.source).toBe("asset")
		expect(resolved.tintRole).toBe("content")
		-- a package that skins ONE icon keeps its own there and takes the
		-- framework's for the others
		local partial = themes.define(withIcons({ ["close"] = "cross" }))
		expect(themes.resolveIcon(partial, "close").assetName).toBe("cross")
		expect(themes.resolveIcon(partial, "chevron.down").source).toBe("asset")
		expect(partial.assets[themes.resolveIcon(partial, "chevron.down").assetName]).toBeNil()
	end)

	it("the ASCII glyph when a package DECLINES the framework set — never tofu", function()
		-- the floor is still reachable and still ASCII, which is the property the
		-- whole fallback table exists for: a package that wants characters (a
		-- pixel grid, or a deliberate comparison) says so and gets them.
		local d = def()
		d.identity.standardIcons = false
		local declining = themes.define(d)
		local resolved = themes.resolveIcon(declining, "chevron.trailing")
		expect(resolved.source).toBe("glyph")
		expect(resolved.glyph).toBe(">")
		expect(themes.isSafeGlyph(resolved.glyph)).toBe(true)
	end)

	it("both PAINT PATHS answer for the same tint roles — one word, two subsystems", function()
		-- An icon's colour is written twice: as an `ImageColor3` sheet token in
		-- native mode, and as a literal Color3 from the target's own style in
		-- fallback mode. Both read `tintRole`, so the two vocabularies must be the
		-- SAME vocabulary -- and nothing asserted that until the framework started
		-- shipping art of its own, which is the first time a role travels to
		-- packages that never declared one.
		--
		-- The asymmetry that makes this worth pinning: sheet_model hard-asserts on a
		-- role it does not know, while the fallback path silently paints untinted
		-- white. A role in one table and not the other is therefore a crash on one
		-- device and an invisible icon on another.
		local adapterSrc = fs.readFile("src/client/screen_chrome.luau")
		local fbBlock = string.match(adapterSrc, "local ICON_TINT_COLOR: { %[string%]: Color3 } = {(.-)\n\t}")
		expect(fbBlock ~= nil).toBe(true)
		local fallback: { [string]: boolean } = {}
		for role in string.gmatch(fbBlock :: string, "(%w+) = toColor3") do
			fallback[role] = true
		end
		local nativeSrc = fs.readFile("src/tokens/sheet_model.luau")
		local natBlock = string.match(nativeSrc, "TINT_ROLE_TOKEN[^{]*{(.-)\n}")
		expect(natBlock ~= nil).toBe(true)
		local native: { [string]: boolean } = {}
		for role in string.gmatch(natBlock :: string, '(%w+) = "%$') do
			native[role] = true
		end
		expect(next(fallback) ~= nil).toBe(true)
		for role in fallback do
			expect(native[role]).toBe(true)
		end
		for role in native do
			expect(fallback[role]).toBe(true)
		end
		-- and every role the framework's OWN art names is in that shared vocabulary,
		-- so the set cannot ship a tint neither path can paint
		local standard = require("../src/themes/standard_icons")
		for _, entry in standard.ART :: any do
			expect(native[entry.tintRole]).toBe(true)
		end
	end)

	--[[ THE LEGACY SHEET'S PER-NAME ICON TINT — the rule family that only the
		PACKAGE builder used to emit.

		A managed picture's `ImageColor3` is sheet-owned paint, so with no package
		installed there was no rule at all and every framework icon painted unstyled
		WHITE. That is invisible on the LIGHT built-in style and merely
		indistinguishable from `content` on the dark one, which is why it survived:
		the two styles is what makes it a defect rather than a preference, so both
		are read here. ]]
	it("the legacy sheet tints a framework icon by NAME, in both built-in styles", function()
		local sheetModel = require("../src/tokens/sheet_model")
		local themePackage = require("../src/themes/package")
		local styles = {
			dark = require("../src/tokens/default_style"),
			light = require("../src/tokens/default_light_style"),
		}
		for label, style in styles do
			local model = sheetModel.build({ themes = { { name = `Facet Neutral {label}`, style = style } } })
			local painted: { [string]: string } = {}
			for _, rule in model.rules do
				local tag = string.match(rule.selector, "^%.(facet%-chrome%-icon%-[%w%-]+)$")
				if tag ~= nil and rule.props.ImageColor3 ~= nil then
					painted[tag] = tostring(rule.props.ImageColor3)
				end
			end
			-- every framework name that resolves to a PICTURE has one, and the ones
			-- that answer with a glyph have none (a character is text, not an image)
			local wantArt, wantGlyph = 0, 0
			for name in themePackage.ICON_FALLBACK_GLYPHS :: any do
				local resolved = themePackage.resolveIcon(nil, tostring(name))
				local tag = chrome_slots.iconTagFor(tostring(name))
				if type(resolved) == "table" and resolved.source == "asset" then
					wantArt += 1
					expect(`{label} {name}: {tostring(painted[tag])}`).toBe(`{label} {name}: $Content`)
				else
					wantGlyph += 1
					expect(`{label} {name}: {tostring(painted[tag])}`).toBe(`{label} {name}: nil`)
				end
			end
			-- every one of the framework's own names resolves to a picture today, so
			-- the glyph arm of the loop is empty by construction and says so; the
			-- claim it stands for is asked directly below
			expect(`{label}: art {wantArt > 0}, glyph-only {wantGlyph}`).toBe(`{label}: art true, glyph-only 0`)
			-- ...and a name the framework knows nothing about earns no rule at all
			expect(`{label}: unknown name: {tostring(painted[chrome_slots.iconTagFor("not-an-icon")])}`).toBe(
				`{label}: unknown name: nil`
			)
			-- the token really resolves in that style, which is the half a SPELLED
			-- token (this builder cannot see the role-to-token map) could get wrong
			-- with nothing noticing
			expect(`{label}: $Content resolves: {model.themes[1].tokens.Content ~= nil}`).toBe(
				`{label}: $Content resolves: true`
			)
		end
	end)

	it("a status plate re-letters the picture on it, in BOTH sheet builders", function()
		--[[ AN ICON DECLARES ONE COLOUR PER NAME (`content` for every framework
			status icon), which is right on the page and invisible on a status plate —
			measured live, `status.warning` painted cream on cream. The node that
			carries the picture already knows the answer, because its own lettering IS
			the plate's readable partner, so four scoped rules hand that role to the
			picture. Both builders emit them, and each comes AFTER the per-name tint it
			corrects: the cascade is priority, then insertion, with no selector
			specificity, so position IS the ruling. ]]
		local sheetModel = require("../src/tokens/sheet_model")
		local defaultStyle = require("../src/tokens/default_style")
		local models = {
			legacy = sheetModel.build({ themes = { { name = "Facet Neutral", style = defaultStyle } } }),
			package_ = sheetModel.buildPackage(snapshot.neutralPackage()),
		}
		for label, model in models do
			local found: { string } = {}
			local perName, lastPerName, lastStatus = 0, 0, 0
			for index, rule in model.rules do
				local role = string.match(rule.selector, "^%.facet%-letters%-(%w+) > %.facet%-chrome%-icon$")
				if role ~= nil then
					table.insert(found, `{role}={tostring(rule.props.ImageColor3)}`)
					lastStatus = index
				elseif string.find(rule.selector, chrome_slots.ICON_TAG_PREFIX, 1, true) ~= nil then
					-- a per-NAME icon tint. `~= nil`, NOT `== 1`: every selector starts
					-- with the dot, so the old test returned 2 and never fired — the
					-- ordering claim below was vacuously true in both builders
					perName += 1
					lastPerName = index
				end
			end
			table.sort(found)
			-- five roles, not four: `contentStrong` is the lettering a control OVER
			-- MEDIA takes, and its picture follows its word there for the same reason
			expect(`{label}: {table.concat(found, " ")}`).toBe(
				`{label}: contentStrong=$ContentStrong onAccent=$OnAccent onDanger=$OnDanger `
					.. `onSuccess=$OnSuccess onWarning=$OnWarning`
			)
			--[[ ORDER MEANS SOMETHING IN BOTH BUILDERS NOW: each emits one tint per
				icon NAME that resolves to art — the package builder over the union of its
				own art and the framework's, the legacy one over the framework set a game
				with no package installed actually reaches — and the lettering rules have
				to come after all of them. ]]
			expect(`{label}: per-name {perName > 0}, status after them {lastStatus > lastPerName}`).toBe(
				`{label}: per-name true, status after them true`
			)
			--[[ ...AND NOTHING LATER REPAINTS THE PICTURE, which is the claim the
				ordering is FOR (the `button_shape` idiom: a later rule on a selector this
				node matches would win on the same property). ]]
			for index = lastStatus + 1, #model.rules do
				local rule = model.rules[index]
				local touchesPicture = string.find(rule.selector, chrome_slots.ICON_PICTURE_TAG, 1, true) ~= nil
					or string.find(rule.selector, chrome_slots.ICON_TAG_PREFIX, 1, true) ~= nil
				expect(`{label}/{rule.name}: {touchesPicture and rule.props.ImageColor3 ~= nil}`).toBe(
					`{label}/{rule.name}: false`
				)
			end
			-- ...and every token those rules spend really exists in every theme, or a
			-- swap would stop painting the picture
			for _, theme in model.themes do
				for _, role in sheetModel.STATUS_LETTERS do
					local token = theme.tokens[role:sub(1, 1):upper() .. role:sub(2)]
					expect(`{label}/{theme.name}/{role}: {type(token) == "table"}`).toBe(
						`{label}/{theme.name}/{role}: true`
					)
				end
			end
		end
	end)

	it("nothing at all for a name that means nothing, at every rung", function()
		expect(themes.resolveIcon(snapshot.neutralPackage(), "not.an.icon")).toBeNil()
		-- with no package at all there is nothing to override the framework, so
		-- its own art answers
		expect(themes.resolveIcon(nil, "close").source).toBe("asset")
		expect(themes.resolveIcon(nil, "not.an.icon")).toBeNil()
	end)
end)

describe("Pixel Quest action icon coverage", function()
	it("fills missing action artwork while preserving its own pixel art and explicit glyph demo", function()
		local theme = require("../examples/themes/pixel_quest")
		local f = require("../src")
		local package = theme.build(f.themes)
		for _, name in { "menu", "flag", "facet:search", "close" } do
			expect(themes.resolveIcon(package, name).source).toBe("asset")
		end
		expect(themes.resolveIcon(package, "close").contentId ~= themes.resolveIcon(nil, "close").contentId).toBe(true)
		expect(themes.resolveIcon(theme.buildWithoutIcons(f.themes), "menu").source).toBe("glyph")
	end)
end)

describe("search icon follows the existing theme resolver", function()
	it("shipped glyph-oriented themes still draw a real magnifying glass", function()
		for _, theme in
			{
				require("../examples/themes/pixel_quest"),
				require("../examples/themes/compact_pointer"),
				require("../examples/themes/glossy_touch"),
			}
		do
			local search = themes.resolveIcon(theme.build(require("../src").themes), "facet:search")
			expect(search.source).toBe("asset")
			expect(search.contentId).toBe(themes.resolveIcon(nil, "facet:search").contentId)
			expect(search.tintRole).toBe("content")
		end
	end)
	it("uses tinted standard art, honors package art, and keeps the explicit ASCII floor", function()
		local neutral = snapshot.neutralPackage()
		local search = themes.resolveIcon(neutral, "facet:search")
		expect(search.source).toBe("asset")
		expect(search.contentId).toBe("rbxassetid://85188541706347")
		expect(search.tintRole).toBe("content")
		local model = require("../src/tokens/sheet_model").buildPackage(neutral)
		local searchRule = nil
		for _, rule in model.rules do
			if rule.name == "Icon — facet:search" then
				searchRule = rule
			end
		end
		expect(searchRule ~= nil).toBe(true)
		expect(searchRule.props.ImageColor3).toBe("$Content")
		local custom = themes.define(withIcons({ ["facet:search"] = "caret" }))
		local override = themes.resolveIcon(custom, "facet:search")
		expect(override.contentId).toBe("rbxassetid://31")
		expect(override.tintRole).toBe("accent")
		local d = def()
		d.identity.standardIcons = false
		local fallback = themes.resolveIcon(themes.define(d), "facet:search")
		expect(fallback.source).toBe("glyph")
		expect(fallback.glyph).toBe("o/")
		expect(themes.isSafeGlyph(fallback.glyph)).toBe(true)
	end)
end)
