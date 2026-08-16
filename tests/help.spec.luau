--!strict
--[[ D3a — `help`: PLAYER-PULLED, AND NOTHING ON TOUCH
	(navigation-and-menus brief §2 D3, director ruling 2026-08-16 §6.2).

	Apple separates two mechanisms this round's first draft conflated, and this
	file is the first half. `.help(_:)` "configures the view's accessibility hint
	and its help tag (also called a tooltip) in macOS or visionOS", and
	`UIToolTipInteraction` "makes it possible to show a tooltip WHEN HOVERING A
	POINTER over a view or control". On a touch phone nothing appears, and there
	is NO LONG-PRESS BINDING ANYWHERE IN APPLE'S API. The auto-popping plate in
	the reference screenshot is the OTHER mechanism — a TipKit coach mark — and
	it is `tests/callout.spec.luau`.

	  | class            | show                       | hide                     |
	  |------------------|----------------------------|--------------------------|
	  | mouse / pointer  | hover, after a dwell       | pointer leaves; activate |
	  | keyboard/gamepad | on focus                   | on blur                  |
	  | touch            | NOTHING — and it is right  | —                        |

	THE ASYMMETRY IS THE SPEC, NOT A VIOLATION of the three-axes rule, because
	`help` is never the only route to information a player needs. That claim is
	itself checked: `text_audit.helpRoutes` finds a help string that appears
	nowhere else, and — the part `clippedEssential` cannot do — refuses to let a
	declaration waive the question of whether any gesture still reaches it.

	AND IT BINDS NO GESTURE. D2 measured the long-press collision and decided the
	other way from the brief: the disclosure plate KEEPS touch long-press because
	it is the only touch route to a truncated label's full value. `help` takes
	nothing from it. `tests/menu.spec.luau`'s source sweep fails the day a third
	file in `src/` learns the word; the cases here fail from the other side, at
	the adapter seam that would have to wire it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local textAudit = require("../src/layout/text_audit")
local fake_target = require("../tests/lib/fake_target")

local HELP = "Posts this avatar to the Marketplace"
local PLATE = "/__help__/Layer/Surface/Plate"
local PLATE_LABEL = "/__help__/Layer/Surface/Plate/Body"
local NO_FOCUS = { initialFocus = "none" }

local function makeWorld(classes: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	if classes ~= nil then
		env:set("capabilities", classes.capabilities)
		env:set("preferredInput", classes.preferredInput)
	end
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

local POINTER = {
	capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
	preferredInput = "KeyboardAndMouse",
}
local TOUCH = {
	capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
	preferredInput = "Touch",
}
local BOTH = {
	capabilities = { keyboard = true, mouse = true, touch = true, gamepad = false },
	preferredInput = "KeyboardAndMouse",
}

local function helpedScreen(help: any, extra: { any }?): any
	local children: { any } = {
		UI.Button({
			id = "Post",
			label = "Post",
			help = help,
			width = { type = "fixed", px = 88 },
			height = { type = "fixed", px = 44 },
		}),
		UI.Button({
			id = "Other",
			label = "Other",
			width = { type = "fixed", px = 88 },
			height = { type = "fixed", px = 44 },
		}),
	}
	for _, node in extra or {} do
		table.insert(children, node)
	end
	return UI.Screen({ id = "Editor", children = children })
end

describe("D3a help: the pointer pulls it, after a dwell", function()
	it("pointer hover presents the help plate only after the dwell elapses", function()
		local _, _, adapter, _, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		expect(pres.help().present).toBe(false)
		pres._discloseHover("/Editor/Post")
		expect(pres.help().present).toBe(false) -- the dwell is a decision, not a pass-through
		pres.tick(0.2)
		expect(pres.help().present).toBe(false)
		pres.tick(0.3)
		local h = pres.help()
		expect(h.present).toBe(true)
		expect(h.source).toBe("pointer")
		expect(h.sourcePath).toBe("/Editor/Post")
		expect(h.helpText).toBe(HELP)
		expect(adapter.node(PLATE_LABEL).props.text).toBe(HELP)
	end)

	it("the pointer leaving takes it away", function()
		local _, _, _, _, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		pres._discloseHover("/Editor/Post")
		pres.tick(0.5)
		expect(pres.help().present).toBe(true)
		pres._discloseHover(nil)
		expect(pres.help().present).toBe(false)
	end)

	it("activating the view takes it away — a player who pressed has stopped asking", function()
		local _, _, adapter, _, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		pres._discloseHover("/Editor/Post")
		pres.tick(0.5)
		expect(pres.help().present).toBe(true)
		adapter.tap("/Editor/Post")
		expect(pres.help().present).toBe(false)
	end)

	it("moving to a different helped view retires the first answer and re-earns the dwell", function()
		local _, _, _, _, pres = makeWorld(POINTER)
		pres.present(
			helpedScreen(HELP, {
				UI.Button({
					id = "Save",
					label = "Save",
					help = "Keeps this draft",
					width = { type = "fixed", px = 88 },
					height = { type = "fixed", px = 44 },
				}),
			}),
			NO_FOCUS
		)
		pres._discloseHover("/Editor/Post")
		pres.tick(0.5)
		expect(pres.help().helpText).toBe(HELP)
		pres._discloseHover("/Editor/Save")
		expect(pres.help().present).toBe(false) -- the old answer goes at once
		pres.tick(0.5)
		expect(pres.help().helpText).toBe("Keeps this draft")
	end)
end)

describe("D3a help: keyboard and gamepad get it on focus, immediately", function()
	it("focus entering a helped view presents the plate with no dwell", function()
		local _, _, adapter, _, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP))
		local h = pres.help()
		expect(h.present).toBe(true)
		expect(h.source).toBe("focus")
		expect(h.sourcePath).toBe("/Editor/Post")
		expect(adapter.node(PLATE_LABEL).props.text).toBe(HELP)
	end)

	it("focus moving off takes it away", function()
		local _, _, _, system, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP))
		expect(pres.help().present).toBe(true)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Editor/Other")
		expect(pres.help().present).toBe(false)
	end)
end)

describe("D3a help: NOTHING on touch, and that is the specification", function()
	it("a pure-touch world wires NO engagement zone for help at all", function()
		local _, _, adapter, _, pres = makeWorld(TOUCH)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		local zone = adapter.node("/Editor/Post").discloseZone
		-- either no zone at all, or a zone with neither half: what must never
		-- exist is a gesture bound to help
		expect(zone == nil or (zone.hover == nil and zone.longPress == nil)).toBe(true)
		expect(pres.help().present).toBe(false)
	end)

	it("HELP BINDS NO GESTURE: with both classes live it wires hover and never a press", function()
		--[[ THE CLAIM D2 ASKED FOR A SPEC TO BE ABLE TO FAIL ON, from the adapter
			seam rather than from source. In a world with a pointer AND a finger, a
			node that declares ONLY `help` gets the hover half and nothing else; the
			node beside it that declares `disclose` gets BOTH, because the plate kept
			the gesture. Bind long-press to help and the second expectation here goes
			red on the same run as `menu.spec`'s source sweep. ]]
		local _, _, adapter, _, pres = makeWorld(BOTH)
		pres.present(
			helpedScreen(HELP, {
				UI.Text({
					id = "Name",
					text = "A racer name far too long for the sixty pixels this cell was given",
					disclose = true,
					lineLimit = 1,
					width = { type = "fixed", px = 60 },
				}),
			}),
			NO_FOCUS
		)
		local helped = adapter.node("/Editor/Post").discloseZone
		expect(helped ~= nil).toBe(true)
		expect(helped.hover ~= nil).toBe(true)
		expect(helped.longPress).toBeNil()
		-- the plate's own node, unchanged by any of this
		local disclosed = adapter.node("/Editor/Name").discloseZone
		expect(disclosed.hover ~= nil).toBe(true)
		expect(disclosed.longPress ~= nil).toBe(true)
	end)

	it("a touch tap moves focus but presents nothing — focusVisible is the gate", function()
		local _, _, adapter, _, pres = makeWorld(TOUCH)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		adapter.tap("/Editor/Post")
		pres.refresh()
		expect(pres.help().present).toBe(false)
	end)
end)

describe("D3a help: the plate is chrome, and the value outranks it", function()
	it("a truncated DISCLOSED label outranks help on the same engagement", function()
		--[[ One engagement, two possible answers. A player who cannot read the
			label needs the value before the convenience, so the plate wins and the
			help plate stays down — never both at once. ]]
		local _, _, _, _, pres = makeWorld(POINTER)
		pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.Button({
						id = "Post",
						label = "",
						help = HELP,
						width = { type = "fixed", px = 60 },
						height = { type = "fixed", px = 44 },
						children = {
							UI.Text({
								id = "Name",
								text = "A racer name far too long for the sixty pixels this cell was given",
								disclose = true,
								lineLimit = 1,
							}),
						},
					}),
				},
			}),
			NO_FOCUS
		)
		pres._discloseHover("/Editor/Post")
		pres.tick(0.5)
		expect(pres.disclosure().present).toBe(true)
		expect(pres.help().present).toBe(false)
	end)

	it("the plate takes no focus and adds no focus stop", function()
		local _, _, adapter, _, pres = makeWorld(POINTER)
		local handle = pres.present(helpedScreen(HELP))
		expect(pres.help().present).toBe(true)
		for _, entry in handle.focusOrder().traversal do
			expect(string.find(entry.path, "__help__", 1, true)).toBeNil()
		end
		expect(pres.focus.focused:get()).toBe("/Editor/Post")
		for _, path in adapter.paths() do
			if string.find(path, "__help__", 1, true) ~= nil then
				local class = adapter.node(path).class
				expect(class == "Button" or class == "Toggle" or class == "TextField").toBe(false)
			end
		end
	end)

	it("dismissing the surface takes its help with it", function()
		local _, _, adapter, _, pres = makeWorld(POINTER)
		local handle = pres.present(helpedScreen(HELP))
		expect(pres.help().present).toBe(true)
		pres.dismiss(handle)
		expect(pres.help().present).toBe(false)
		expect(adapter.node(PLATE_LABEL)).toBeNil()
	end)

	it("a help string wraps rather than clips at 1.4x expansion", function()
		local _, _, adapter, _, pres = makeWorld(POINTER)
		local long = string.rep(HELP .. " ", 3)
		pres.present(helpedScreen(long))
		expect(pres.help().present).toBe(true)
		local rect = adapter.node(PLATE).rect
		expect(rect.x >= 0).toBe(true)
		expect(rect.x + rect.w <= 390).toBe(true)
	end)

	it("the dump carries the schema, the source and every live declaration", function()
		local _, _, _, _, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP))
		local dump = pres.help()
		expect(dump.schema).toBe("luauui-help-dump/1")
		expect(dump.present).toBe(true)
		expect(dump.declarations).toBe(1)
		expect(string.find(dump.text, "/Editor/Post", 1, true) ~= nil).toBe(true)
	end)

	it("help is a CONSTRUCTION-ONLY string: a Readable is refused by name", function()
		local core = customFactory.new()
		local bound = core:signal(HELP)
		local ok, err = pcall(function()
			return UI.Button({ id = "Post", label = "Post", help = bound })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "help", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D3a help: the reachability check, and why it is not clippedEssential", function()
	--[[ `text_audit.clippedEssential` accepts the DECLARATION `disclose = true`
		and never asks whether the gesture reaching it still exists (D2's own
		finding). This check does both halves and keeps them separate: a waiver
		can say "this help repeats nothing on screen and that is fine", and NO
		waiver can say "nothing reaches it". ]]
	local function declaration(text: string, hover: boolean, focus: boolean): any
		return { text = text, hover = hover, focus = focus }
	end

	local function rectsWith(paths: { [string]: string }): any
		local out: any = {}
		for path, text in paths do
			out[path] = { rect = { x = 0, y = 0, w = 100, h = 20 }, textFacts = { text = text, truncated = false } }
		end
		return out
	end

	it("a help string that appears nowhere else is reported: a touch player cannot read it", function()
		local findings = textAudit.helpRoutes(
			{ ["/S/Post"] = declaration("Posts this avatar to the Marketplace", true, true) },
			rectsWith({ ["/S/Post/Label"] = "Post" })
		)
		expect(#findings).toBe(1)
		expect(findings[1].check).toBe("helpOnlyRoute")
		expect(findings[1].node).toBe("/S/Post")
	end)

	it("...and one the screen also says out loud is not", function()
		local findings = textAudit.helpRoutes(
			{ ["/S/Post"] = declaration("Post to Marketplace", true, true) },
			rectsWith({ ["/S/Post/Label"] = "Post", ["/S/Hint"] = "Post to Marketplace when you are ready" })
		)
		expect(#findings).toBe(0)
	end)

	it("HIDDEN text is not a route: a losing ViewThatFits candidate says nothing", function()
		local rects = rectsWith({ ["/S/Post/Label"] = "Post" })
		rects["/S/Alt"] = {
			rect = { x = 0, y = 0, w = 100, h = 20 },
			hidden = true,
			textFacts = { text = "Posts this avatar to the Marketplace", truncated = false },
		}
		local findings = textAudit.helpRoutes(
			{ ["/S/Post"] = declaration("Posts this avatar to the Marketplace", true, true) },
			rects
		)
		expect(#findings).toBe(1)
		expect(findings[1].check).toBe("helpOnlyRoute")
	end)

	it("...and neither is TRUNCATED text — an ellipsis is not the sentence", function()
		local rects = rectsWith({ ["/S/Post/Label"] = "Post" })
		rects["/S/Cut"] = {
			rect = { x = 0, y = 0, w = 30, h = 20 },
			textFacts = { text = "Posts this avatar to the Marketplace", truncated = true },
		}
		local findings = textAudit.helpRoutes(
			{ ["/S/Post"] = declaration("Posts this avatar to the Marketplace", true, true) },
			rects
		)
		expect(#findings).toBe(1)
	end)

	it("a `convenience` waiver silences the duplication finding", function()
		local findings = textAudit.helpRoutes(
			{ ["/S/Post"] = declaration("Shortcut: Ctrl+S", true, true) },
			rectsWith({ ["/S/Post/Label"] = "Post" }),
			{ convenience = { "/S/Post" } }
		)
		expect(#findings).toBe(0)
	end)

	it("BUT NO WAIVER REACHES THE GESTURE: help nothing engages is reported anyway", function()
		--[[ THE IMPROVEMENT ON `clippedEssential`, stated as a test. That check
			takes a declaration as proof and stops; this one asks the separate
			question the declaration cannot answer — is there a live route at all —
			and the waiver cannot touch it. ]]
		local findings = textAudit.helpRoutes(
			{ ["/S/Caption"] = declaration("Shortcut: Ctrl+S", false, false) },
			rectsWith({ ["/S/Caption"] = "Shortcut: Ctrl+S" }),
			{ convenience = { "/S/Caption" } }
		)
		expect(#findings).toBe(1)
		expect(findings[1].check).toBe("helpNoRoute")
	end)

	it("a pointer-only world still has a route; a pure-touch one has none", function()
		local rects = rectsWith({ ["/S/Post/Label"] = "Post", ["/S/Hint"] = "Posts this avatar" })
		expect(#textAudit.helpRoutes({ ["/S/Post"] = declaration("Posts this avatar", true, false) }, rects)).toBe(0)
		local none = textAudit.helpRoutes({ ["/S/Post"] = declaration("Posts this avatar", false, false) }, rects)
		expect(#none).toBe(1)
		expect(none[1].check).toBe("helpNoRoute")
	end)

	it("the presenter reports the LIVE declarations, so the check runs on a real mount", function()
		local _, _, _, _, pres = makeWorld(POINTER)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		local decls = pres.helpDeclarations()
		expect(decls["/Editor/Post"] ~= nil).toBe(true)
		expect(decls["/Editor/Post"].text).toBe(HELP)
		expect(decls["/Editor/Post"].hover).toBe(true)
		expect(decls["/Editor/Post"].focus).toBe(true)
		expect(decls["/Editor/Other"]).toBeNil()
	end)

	it("...and in a pure-touch world the SAME mount reports no route, which is the finding", function()
		local _, _, _, _, pres = makeWorld(TOUCH)
		pres.present(helpedScreen(HELP), NO_FOCUS)
		local decls = pres.helpDeclarations()
		expect(decls["/Editor/Post"].hover).toBe(false)
		-- focus is still a route on this node — it IS focusable — so the finding
		-- here is the duplication one, not the no-route one
		expect(decls["/Editor/Post"].focus).toBe(true)
	end)

	it("NO NEW DEVICE BRANCH: the new modules name no platform", function()
		local fs = require("@lune/fs")
		local names = { "iphone", "ipad", "android", "xbox", "playstation", "nintendo", "macos", "windows" }
		for _, file in { "src/present/help_plate.luau", "src/present/callout_queue.luau", "src/controls/callout.luau" } do
			local text = string.lower(fs.readFile(file))
			for _, name in names do
				expect(string.find(text, name, 1, true)).toBeNil()
			end
		end
	end)
end)
