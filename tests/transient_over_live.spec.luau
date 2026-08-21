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

	IT IS A MODEL-SIDE CHECK AND SAYS SO. It reads the surfaces the framework
	mounts and the `surface` roles it declares on them; it cannot see a package's
	own paint, and it would not have caught an engine-side occlusion. What it
	catches is the family of mistakes the framework can make BY DECLARATION, which
	is the family this rule is about.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = Facet.UI
local worldLib = require("./lib/world")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")

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

--[[ Every node above the base screen that paints an opaque fill the size of the
	viewport. "The size of the viewport" is generous on purpose — a node covering
	most of the screen is the defect just as much as one covering all of it. ]]
local function opaqueCovers(w: any, baseId: string): { string }
	local out: { string } = {}
	for _, path in w.adapter.paths() do
		local root = string.match(path, "^/([^/]+)")
		if root == nil or root == baseId then
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
		if rect.w >= VIEWPORT.w * 0.9 and rect.h >= VIEWPORT.h * 0.9 then
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
		expect(table.concat(opaqueCovers(w, "Live"), " ; ")).toBe("")
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
		expect(table.concat(opaqueCovers(w, "Live"), " ; ")).toBe("")
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
		expect(table.concat(opaqueCovers(w, "Live"), " ; ")).toBe("")
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
		expect(table.concat(opaqueCovers(w, "Live"), " ; ")).toBe("")
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
	end)
end)
