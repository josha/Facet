--!strict
--[[ A TRANSIENT OPENED FROM A CONTROL APPEARS OVER THE LIVE SCREEN.

	THE DIRECTOR'S RULE (2026-08-21, from a live showcase session): a menu, a
	popup, a picker panel, a callout, an expand plate — the whole anchored-surface
	family — opens ON TOP of the screen that is already there, and that screen
	STAYS VISIBLE behind it. A full-screen opaque fill behind a transient is
	banned. The observation that commissioned it was a picker list standing over a
	flat opaque rectangle where the mounted demo had been, and the director's note
	beside it: "I've now seen that issue a couple times with menus from buttons."

	WHY A RULE AND NOT A BUG REPORT. Every one of these surfaces is built by a
	different construct — `newMenu` presents a modal anchored panel, `PopupButton`
	presents a transient one, `region_expand` presents a plate, the presenter
	synthesizes a scrim beneath an exclusive surface — and each one could grow its
	own full-screen backdrop without any of the others noticing. What they share is
	the shape of the mistake: a node the FRAMEWORK synthesized, the size of the
	viewport, painted with an opaque surface, above the base. That is one predicate,
	and it is what this file asserts over the family.

	IT IS A MODEL-SIDE CHECK AND SAYS SO. It reads the surfaces on the stack and the
	`surface` roles declared on them; it cannot see an image skin or an explicit
	colour, and it would not have caught an engine-side occlusion. What it catches
	is the family of mistakes that are made BY DECLARATION, which is the family this
	rule is about.

	=== WHAT THE FIRST VERSION OF THIS FILE DID NOT DO (review of `48b6e7b`) ===

	It was copied into the PARENT export — the commit that still had the defect —
	and passed there, 5/5. A guard that is green on the thing it was commissioned by
	is a guard about something else, and three separate reasons were found:

	  1. ONE OF ITS FOUR CASES WAS INERT. The size threshold was a module-level
	     `VIEWPORT` constant while the expand-plate case built its world 390x40, so
	     `rect.h >= 844 * 0.9` could never be true there and the case's only live
	     assertion was `depth() == 2`. The threshold is derived from the world's own
	     viewport now, which is what makes "most of the screen" mean anything.
	  2. IT ASSUMED ONE BASE SCREEN. `opaqueCovers(w, baseId)` skipped exactly one
	     root; the app in the photograph has two live base surfaces (a permanent
	     backdrop AND the demo on top of it). A SET is skipped now, and the demo
	     roots that declare `surface = "base"` themselves are the class the
	     photograph is actually made of.
	  3. THE PACKAGE CASE READ THE NEUTRAL MODEL AND WAS TITLED "every shipped
	     package". All eight ship their own scrim opacity (0.3 … 0.55) and none of
	     them was read; a package shipping `scrimOpacity = 0` would have been a fully
	     opaque scrim with the suite green. The loop is the whole fix.

	And the case the whole rule exists for — a transient standing over a LIVE screen
	that re-presents underneath it — is now driven through the construct that
	commissioned it: the showcase's own picker panel. That case fails at `130dcae`
	and passes at `48b6e7b`, which is the only definition of this file working.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = Facet.UI
local worldLib = require("./lib/world")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")
local themes = Facet.themes
local demo_picker = require("../examples/gallery/client/demo_picker")
local settings_panel = require("../examples/gallery/client/settings_panel")
local showcase_chrome = require("../examples/gallery/client/showcase_chrome")

-- the eight packages the showcase ships, minus the deliberately-degenerate
-- fixtures — the same list `gallery_chrome.spec` sweeps
local SHIPPED_PACKAGES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

-- the surface roles that PAINT: a node wearing one of these is a fill, not a box
-- (`plain` and `scrim` are the two the sheet suppresses or dims deliberately)
local OPAQUE_SURFACE: { [string]: boolean } = {
	base = true,
	raised = true,
	control = true,
	chip = true,
	badge = true,
	accent = true,
}

local VIEWPORT = { x = 0, y = 0, w = 390, h = 844 }

--[[ Every node above the base screens that paints an opaque fill the size of the
	viewport. "The size of the viewport" is generous on purpose — a node covering
	most of the screen is the defect just as much as one covering all of it.

	THE THRESHOLD IS THE WORLD'S OWN VIEWPORT, read live (finding 1 above). A
	module constant is a threshold about a DIFFERENT world, and a case that builds a
	shorter one can never trip it.

	`base` IS A SET, not one id (finding 2). An app with a permanent backdrop under
	a swappable screen has two live base surfaces, and a predicate that can skip
	only one reports the other as a violation of a rule it is not breaking. ]]
local function opaqueCovers(w: any, base: { [string]: boolean }): { string }
	local out: { string } = {}
	local vp = w.env:get("viewportRect"):get()
	local minW = (if type(vp) == "table" and type(vp.w) == "number" then vp.w else VIEWPORT.w) * 0.9
	local minH = (if type(vp) == "table" and type(vp.h) == "number" then vp.h else VIEWPORT.h) * 0.9
	for _, path in w.adapter.paths() do
		local root = string.match(path, "^/([^/]+)")
		if root == nil or base[root] == true then
			continue
		end
		local node = w.adapter.node(path)
		local rect = if node ~= nil then node.rect else nil
		if rect == nil or w.adapter.visibleOf(path) == false then
			continue
		end
		local surface = if type(node.props) == "table" then node.props.surface else nil
		if type(surface) ~= "string" or not OPAQUE_SURFACE[surface] then
			continue
		end
		if rect.w >= minW and rect.h >= minH then
			table.insert(out, `{path} ({surface}) {rect.w}x{rect.h}`)
		end
	end
	table.sort(out)
	return out
end

-- a base screen with something on it, so "the live screen" is a real thing
local function liveScreen(): any
	return UI.Screen({
		id = "Live",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.VStack({
				id = "Body",
				surface = "raised",
				padding = "s",
				children = {
					UI.Text({ id = "Headline", text = "the live screen", textSize = 18 }),
					UI.Button({ id = "Trigger", label = "open", onActivate = function() end }),
				},
			}),
		},
	})
end

describe("the standing rule: a transient opens OVER the live screen", function()
	it("an anchored panel adds no opaque full-viewport node", function()
		local w = worldLib.new({ viewport = VIEWPORT })
		w.present(liveScreen(), { initialFocus = "none" })
		w.pres.presentAnchored(
			UI.VStack({
				id = "Panel",
				surface = "raised",
				padding = "s",
				width = { type = "fixed", px = 200 },
				children = { UI.Text({ id = "Row", text = "one", textSize = 16 }) },
			}),
			{ id = "Tip", anchor = { source = { path = "/Live/Body/Trigger" } }, initialFocus = "none" }
		)
		w.pres.refresh()
		expect(table.concat(opaqueCovers(w, { Live = true }), " ; ")).toBe("")
	end)

	it("...and neither does a MODAL anchored panel, whose scrim is the catcher", function()
		local w = worldLib.new({ viewport = VIEWPORT })
		w.present(liveScreen(), { initialFocus = "none" })
		w.pres.presentAnchored(
			UI.VStack({
				id = "Panel",
				surface = "raised",
				padding = "s",
				width = { type = "fixed", px = 200 },
				children = { UI.Button({ id = "One", label = "one", onActivate = function() end }) },
			}),
			{
				id = "Menu",
				modal = true,
				scrim = "none",
				outsideTapCancel = true,
				anchor = { source = { path = "/Live/Body/Trigger" } },
			}
		)
		w.pres.refresh()
		expect(table.concat(opaqueCovers(w, { Live = true }), " ; ")).toBe("")
	end)

	it("...and neither does a region's EXPAND plate", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 40 } })
		w.present(
			UI.Screen({
				id = "Live",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Composition({
						id = "C",
						arrangements = { "column" },
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						groups = { { id = "body", lane = "main", sizing = "fill" } },
						children = {
							UI.Region({
								id = "Clock",
								group = "body",
								rank = 1,
								recover = "overflow",
								children = {
									UI.VStack({
										id = "Full",
										surface = "raised",
										children = {
											UI.Text({ id = "A", text = "2:14", textSize = 16 }),
											UI.Text({ id = "B", text = "12 - 9", textSize = 16 }),
											UI.Text({ id = "C", text = "home 12", textSize = 16 }),
										},
									}),
									UI.Text({ id = "Compact", text = "2:14", textSize = 16 }),
								},
							}),
						},
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		w.adapter.tap("/Live/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		expect(table.concat(opaqueCovers(w, { Live = true }), " ; ")).toBe("")
	end)

	it("a MODAL's declared scrim is the one full-viewport node, and it is the scrim role", function()
		local w = worldLib.new({ viewport = VIEWPORT })
		w.present(liveScreen(), { initialFocus = "none" })
		w.pres.presentModal(
			UI.Screen({
				id = "Sheet",
				children = {
					UI.VStack({
						id = "Card",
						surface = "raised",
						padding = "s",
						children = { UI.Button({ id = "Ok", label = "ok", onActivate = function() end }) },
					}),
				},
			}),
			{ scrim = "scrim" }
		)
		w.pres.refresh()
		--[[ A scrim IS full-viewport by design — it is the dim. What it may not be
			is one of the PAINTING roles: it wears `scrim`, whose transparency the
			theme owns, so the screen behind it stays visible through it. ]]
		expect(table.concat(opaqueCovers(w, { Live = true }), " ; ")).toBe("")
		local found = false
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			local props = if node ~= nil and type(node.props) == "table" then node.props else {}
			if props.surface == "scrim" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)

	it("the theme's scrim is translucent — every shipped package, not just the neutral one", function()
		--[[ The rule's other half: a declared scrim dims, it does not replace. Read
			off the built sheet rather than the token table, because the sheet is what
			paints. ]]
		local function scrimTransparency(model: any): number?
			for _, rule in model.rules do
				if rule.name == sheet_model.SCRIM_RULE then
					local prop = rule.props.BackgroundTransparency
					if type(prop) == "table" and prop.kind == "number" then
						return prop.value
					end
				end
			end
			return nil
		end
		local neutral = scrimTransparency(sheet_model.build({
			themes = {
				{ name = "Dark", style = default_style },
				{ name = "Light", style = light_style },
			},
		}))
		expect(`the neutral scrim is translucent: {neutral ~= nil and neutral > 0 and neutral < 1}`).toBe(
			"the neutral scrim is translucent: true"
		)
		--[[ ...AND THE EIGHT THIS TITLE PROMISES (review finding 3). Every shipped
			package compiles its own `SCRIM_RULE` through `buildPackage`, and the
			numbers differ per package (0.3 … 0.55) — so reading the neutral model and
			calling it "every package" left eight real answers unread, one of which
			could have been a fully opaque scrim. ]]
		local report: { string } = {}
		for _, name in SHIPPED_PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local value = scrimTransparency(sheet_model.buildPackage(pkg))
			local ok = type(value) == "number" and value > 0 and value < 1
			table.insert(report, `{name}={if value == nil then "none" else tostring(value)}:{ok}`)
		end
		table.sort(report)
		local want: { string } = {}
		for _, row in report do
			table.insert(want, `{string.match(row, "^[^=]+=[^:]+")}:true`)
		end
		expect(table.concat(report, " ")).toBe(table.concat(want, " "))
		expect(#report).toBe(#SHIPPED_PACKAGES)
	end)
end)

--[[ THE CASE THE RULE WAS COMMISSIONED BY, driven through the construct that
	produced the photograph.

	The three cases above are the FRAMEWORK's own transients, and every one of them
	is presented once and never disturbed. The photograph is a different shape: a
	picker panel standing over a live screen that RE-PRESENTS underneath it. Cross
	surface z is present order, `displayLayer` only goes up, and a demo swap
	dismisses and re-presents the demo — so the screen the player is reading the
	panel OVER climbs on top of it, and what is left on screen is that screen's own
	opaque `surface = "base"` root with the panel gone underneath.

	THIS IS THE CASE THAT REDDENS AT `130dcae`, which is the whole point of the
	rebuild: run there, the panel ends up below the demo and the predicate reports
	the demo's own full-viewport base fill standing over it.

	TWO BASE ROOTS ON PURPOSE — a permanent backdrop and a swappable demo — because
	that is the arrangement in the photograph and it is what the one-id version of
	the predicate could not describe. ]]
describe("the standing rule, on the surface that commissioned it", function()
	local function showcaseWorld(): any
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 1232, h = 1067 },
			presenterOpts = { keyboardNavigation = true },
		})
		w.pres.present(
			UI.Screen({
				id = "Backdrop",
				surface = "base",
				children = { UI.Spacer({ id = "Fill", width = { type = "fill", weight = 1 } }) },
			}),
			{ responder = "passive", rootPolicy = "edgeToEdge" }
		)
		local chrome: any = nil
		local settings: any = nil
		local demos = demo_picker.mount({
			Facet = Facet,
			core = w.core,
			env = w.env,
			presenter = w.pres,
			composed = true,
			mountDemo = function(demo: any)
				-- A DEMO ROOT THAT DECLARES ITS OWN OPAQUE BASE, which is what the
				-- catalogue really contains (`scenarios/row_actions.luau` mounts
				-- `/MailActions` with `surface = "base"` at full viewport) and what the
				-- flat rectangle in the photograph is made of
				local screen = UI.Screen({
					id = "Demo",
					surface = "base",
					padding = 8,
					children = { UI.Text({ id = "Title", text = demo.title, textSize = 16 }) },
				})
				return { screen = screen, handle = w.pres.present(screen) }
			end,
			onChip = function()
				chrome.request("demos")
			end,
			onChose = function()
				chrome.close()
			end,
			onRaise = function()
				if settings ~= nil then
					settings.apply()
				end
			end,
			warn = function() end,
		})
		settings = settings_panel.mount({
			Facet = Facet,
			core = w.core,
			env = w.env,
			onChip = function()
				chrome.request("settings")
			end,
		})
		chrome = showcase_chrome.mount({
			Facet = Facet,
			core = w.core,
			env = w.env,
			presenter = w.pres,
			actionSystem = w.system,
			demos = demos,
			settings = settings,
			coreTop = w.core:signal(0),
		})
		demos.show(demos.current())
		for _ = 1, 3 do
			w.pres.refresh()
		end
		w.chrome = chrome
		w.demos = demos
		return w
	end

	local BASE_ROOTS = { Backdrop = true, Demo = true, ShowcaseChrome = true }

	it("the picker panel stays over the live screen across demo swaps", function()
		local w = showcaseWorld()
		w.chrome.request("demos")
		for _ = 1, 3 do
			w.pres.refresh()
		end
		expect(table.concat(opaqueCovers(w, BASE_ROOTS), " ; ")).toBe("")
		for _ = 1, 6 do
			w.demos.showNext(1)
			for _ = 1, 3 do
				w.pres.refresh()
			end
		end
		local panel = w.adapter.rootDisplayOrder("ShowcasePanel")
		local demo = w.adapter.rootDisplayOrder("Demo")
		expect(`panel {panel} over the live screen {demo}: {panel > demo}`).toBe(
			`panel {panel} over the live screen {demo}: true`
		)
		--[[ ...AND NOTHING GREW A COVER WHILE IT WAS BEING RAISED. The z-order line
			above is what carries the photographed defect (measured at `130dcae`: panel
			10400 under demo 11000); this is the family predicate re-run after six
			swaps, so a raise that fixed the ordering by synthesizing a full-viewport
			fill would still be caught. The demo's own base root is SKIPPED here on
			purpose — it is a live base screen, not a transient's backdrop — and the
			case below is the control proving the predicate can see it. ]]
		expect(table.concat(opaqueCovers(w, BASE_ROOTS), " ; ")).toBe("")
	end)

	it("the demo's own opaque base IS visible to the predicate — the negative control", function()
		--[[ WITHOUT THIS THE CASE ABOVE PROVES NOTHING: "no opaque cover" is equally
			explained by "this predicate cannot see an app-declared base fill", which is
			exactly the blind spot the review found. Stop skipping the demo root and it
			is reported, by path, at full viewport. ]]
		local w = showcaseWorld()
		w.chrome.request("demos")
		for _ = 1, 3 do
			w.pres.refresh()
		end
		local seen = opaqueCovers(w, { Backdrop = true, ShowcaseChrome = true })
		local found = false
		for _, row in seen do
			if string.match(row, "^/Demo") ~= nil then
				found = true
			end
		end
		expect(`the demo's base fill is visible to the predicate: {found}`).toBe(
			"the demo's base fill is visible to the predicate: true"
		)
	end)
end)
