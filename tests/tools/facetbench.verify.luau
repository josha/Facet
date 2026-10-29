--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Audit = require("../../tools/vendor/verify/src/roblox/ui-audit")
local Rules = require("../../examples/facet-kart/src/shared/RaceRules")
local RaceSpace = require("../../tools/play/host/space")
local Play = require("../../tools/play/host/play")
local Setup = require("../../tools/facet/lib/facetbench_setup")
local Json = require("../../tools/facet/lib/json")
return function(harness: Verify.Harness)
	harness:case(
		"Studio-only preparation restricts every declared model without altering the source catalog",
		function(t)
			local requested = Setup.authorModels(Json.decode([[{"agents":[
			{"adapter":"codex","model":"gpt-6-astra"},
			{"adapter":"codex","model":"gpt-6.1-sol"},
			{"adapter":"codex","model":"gpt-6-astra"}
		]}]]))
			t:expect(#requested):toBe(2)
			local catalog = Json.decode([[{"models":[
			{"slug":"gpt-6-astra","apply_patch_tool_type":"freeform","multi_agent_version":"1","experimental_supported_tools":["shell"],"context_window":100},
			{"slug":"gpt-6.1-sol","apply_patch_tool_type":"freeform","multi_agent_version":"2","experimental_supported_tools":["browser"],"context_window":200},
			{"slug":"unselected","apply_patch_tool_type":"freeform"}
		]}]])
			local before = Json.encode(catalog)
			local models = assert(Json.arrayField(Setup.restrictCatalog(catalog, requested), "models"))
			t:expect(#models):toBe(2)
			for index, model in models do
				local object = assert(Json.asObject(model))
				t:expect(Json.stringField(model, "slug")):toBe(requested[index])
				t:expect(Json.isNull(object.apply_patch_tool_type)):toBe(true)
				t:expect(Json.isNull(object.multi_agent_version)):toBe(true)
				t:expect(#assert(Json.arrayField(model, "experimental_supported_tools"))):toBe(0)
				t:expect(type(Json.field(model, "context_window"))):toBe("number")
			end
			t:expect(Json.encode(catalog)):toBe(before)
		end
	)
	harness:case("Studio-only preparation restricts only Codex models when a Claude author is declared", function(t)
		local requested = Setup.authorModels(Json.decode([[{"agents":[
			{"adapter":"codex","model":"gpt-6.1-sol"},
			{"adapter":"claude-code","model":"claude-opus-5-5"}
		]}]]))
		t:expect(#requested):toBe(1)
		t:expect(requested[1]):toBe("gpt-6.1-sol")
		t:expect(#Setup.authorModels(Json.decode([[{"agents":[{"adapter":"claude-code","model":"claude-opus-5-5"}]}]])))
			:toBe(0)
	end)
	harness:case("Studio-only preparation rejects missing or ambiguous model profiles", function(t)
		for _, source in
			{
				[[{"agents":[]}]],
				[[{"agents":[{"adapter":"codex"}]}]],
				[[{"agents":[{"adapter":"codex","model":""}]}]],
				[[{"agents":[{"adapter":"other","model":"gpt-6-astra"}]}]],
			}
		do
			local accepted = pcall(Setup.authorModels, Json.decode(source))
			t:expect(accepted):toBe(false)
		end
		local missing = pcall(Setup.restrictCatalog, Json.decode([[{"models":[]}]]), { "gpt-6-astra" })
		t:expect(missing):toBe(false)
		local duplicate = pcall(
			Setup.restrictCatalog,
			Json.decode([[{"models":[{"slug":"gpt-6-astra"},{"slug":"gpt-6-astra"}]}]]),
			{ "gpt-6-astra" }
		)
		t:expect(duplicate):toBe(false)
	end)
	harness:case("missing universal device cases are a harness error instead of a zero score", function(t)
		local empty = Verify.createHarness({ now = os.clock })
		empty:case("workspace/builds", { id = "workspace/builds", run = function() end })
		local report = empty:run({ executor = "regression" })
		local ok, problem = pcall(function(): boolean
			Play.validateResults({
				["desktop/universal/hub"] = true,
				["phone-portrait/universal/hub"] = true,
			}, report)
			return true
		end)
		t:expect(ok):toBe(false)
		t:expect(string.find(tostring(problem), "harness error: no recorded result", 1, true) ~= nil):toBe(true)
		local failed = Verify.createHarness({ now = os.clock })
		failed:case("desktop/universal/hub", {
			id = "desktop/universal/hub",
			run = function()
				error("small text")
			end,
		})
		local acceptedFailure =
			pcall(Play.validateResults, { ["desktop/universal/hub"] = true }, failed:run({ executor = "regression" }))
		t:expect(acceptedFailure):toBe(true)
		local transport = Verify.createHarness({ now = os.clock })
		transport:case("desktop/universal/hub", {
			id = "desktop/universal/hub",
			run = function()
				error("harness error: Studio Client call failed: session_lost")
			end,
		})
		local acceptedTransport = pcall(
			Play.validateResults,
			{ ["desktop/universal/hub"] = true },
			transport:run({ executor = "regression" })
		)
		t:expect(acceptedTransport):toBe(false)
	end)
	harness:case("opaque modal branches hide HUD text without hiding actual text overlaps", function(t)
		local value = Audit.decode({
			schemaVersion = 1,
			screen = { width = 390, height = 844, scale = 1, input = { "touch" } },
			roots = {
				{
					index = 1,
					class = "ScreenGui",
					path = "Gui",
					enabled = true,
					world = false,
					zIndexBehavior = "Sibling",
					rect = { x = 0, y = 0, width = 390, height = 844 },
				},
			},
			elements = {
				{
					index = 1,
					root = 1,
					class = "Frame",
					path = "Gui.HUD",
					rect = { x = 0, y = 0, width = 390, height = 844 },
					visible = true,
					zIndex = 1,
					order = 1,
					background = { color = { r = 0, g = 0, b = 0 }, transparency = 1 },
				},
				{
					index = 2,
					parent = 1,
					root = 1,
					class = "TextLabel",
					path = "Gui.HUD.Balance",
					rect = { x = 112, y = 232, width = 191, height = 18 },
					visible = true,
					zIndex = 1,
					order = 2,
					background = { color = { r = 0, g = 0, b = 0 }, transparency = 1 },
					text = {
						content = "Balance",
						size = 18,
						bounds = { width = 191, height = 18 },
						color = { r = 1, g = 1, b = 1 },
						transparency = 0,
					},
				},
				{
					index = 3,
					root = 1,
					class = "Frame",
					path = "Gui.Modal",
					rect = { x = 0, y = 0, width = 390, height = 844 },
					visible = true,
					zIndex = 100,
					order = 3,
					background = { color = { r = 0, g = 0, b = 0 }, transparency = 1 },
				},
				{
					index = 4,
					parent = 3,
					root = 1,
					class = "Frame",
					path = "Gui.Modal.Panel",
					rect = { x = 0, y = 123, width = 390, height = 668 },
					visible = true,
					zIndex = 1,
					order = 4,
					background = { color = { r = 0, g = 0, b = 0 }, transparency = 0 },
				},
				{
					index = 5,
					parent = 4,
					root = 1,
					class = "TextLabel",
					path = "Gui.Modal.Panel.Category",
					rect = { x = 24, y = 229, width = 115, height = 18 },
					visible = true,
					zIndex = 1,
					order = 5,
					background = { color = { r = 0, g = 0, b = 0 }, transparency = 1 },
					text = {
						content = "Part category",
						size = 18,
						bounds = { width = 115, height = 18 },
						color = { r = 1, g = 1, b = 1 },
						transparency = 0,
					},
				},
			},
		})
		local modal, panel = value.elements[3], value.elements[4]
		t:expect(RaceSpace.textClear(value)):toBe(true)
		panel.background.transparency = 0.5
		t:expect(RaceSpace.textClear(value)):toBe(false)
		panel.background.transparency = 0
		modal.zIndex = 0
		t:expect(RaceSpace.textClear(value)):toBe(false)
		modal.zIndex = 100
		panel.rect.width = 120
		t:expect(RaceSpace.textClear(value)):toBe(false)
		panel.rect.width = 390
		local collision = table.clone(value.elements[5])
		collision.index, collision.path, collision.order = 6, "Gui.Modal.Panel.Collision", 6
		table.insert(value.elements, collision)
		t:expect(RaceSpace.textClear(value)):toBe(false)
	end)

	harness:case("race progress requires ordered checkpoints and a forward finish crossing", function(t)
		local racer = { checkpoint = 0, lap = 0, progress = 0 }
		t:expect(Rules.advance(racer, 0.8, true, 16)):toBe(false)
		t:expect(racer.checkpoint):toBe(0)
		t:expect(Rules.advance(racer, 1 / 16, false, 16)):toBe(false)
		t:expect(racer.checkpoint):toBe(0)
		for lap = 1, 3 do
			for checkpoint = 1, 15 do
				t:expect(Rules.advance(racer, checkpoint / 16 + 0.001, true, 16)):toBe(false)
			end
			t:expect(Rules.advance(racer, 0.001, true, 16)):toBe(true)
			t:expect(racer.lap):toBe(lap)
			t:expect(Rules.advance(racer, 0, true, 16)):toBe(false)
		end
	end)
	harness:case("race standings prefer finish order then checkpoint progress and put OUT last", function(t)
		local first = { name = "First", progress = 3, finish = 1, out = false }
		local second = { name = "Second", progress = 3.1, finish = 2, out = false }
		local behind = { name = "Behind", progress = 2.9, finish = math.huge, out = false }
		local out = { name = "Out", progress = 3.2, finish = math.huge, out = true }
		local order = { out, behind, second, first }
		table.sort(order, Rules.ahead)
		t:expect(order[1].name):toBe("First")
		t:expect(order[2].name):toBe("Second")
		t:expect(order[3].name):toBe("Behind")
		t:expect(order[4].name):toBe("Out")
	end)
	harness:case("race safety geometry accepts edge HUDs and rejects center paint and thumbstick actions", function(t)
		local dump: Audit.Dump = {
			schemaVersion = 1,
			screen = {
				width = 390,
				height = 844,
				scale = 1,
				guiInset = { left = 0, top = 0, right = 0, bottom = 0 },
				input = { "touch" },
			},
			roots = {},
			elements = {},
			instances = 1,
			truncated = false,
		}
		local element: Audit.Element = {
			index = 1,
			root = 1,
			class = "TextLabel",
			path = "HUD",
			rect = { x = 140, y = 10, width = 100, height = 40 },
			rotation = 0,
			visible = true,
			zIndex = 1,
			order = 1,
			interactive = false,
			selectable = false,
			active = false,
			interactable = true,
			next = {},
			selectionGroup = false,
			stops = {},
			background = { color = { r = 0, g = 0, b = 0 }, transparency = 0 },
		}
		dump.elements[1] = element
		local actualJump: RaceSpace.TouchRect = { x = 140, y = 10, width = 100, height = 40 }
		element.interactive = true
		t:expect(RaceSpace.touchControlsClear(dump, { actualJump })):toBe(false)
		actualJump.x = 300
		t:expect(RaceSpace.touchControlsClear(dump, { actualJump })):toBe(true)
		local native: RaceSpace.TouchRect = {
			x = element.rect.x,
			y = element.rect.y,
			width = element.rect.width,
			height = element.rect.height,
			path = element.path,
		}
		t:expect(RaceSpace.touchControlsClear(dump, { native })):toBe(true)
		native.path = "PlayerGui.ContextActionGui.OtherButton"
		t:expect(RaceSpace.touchControlsClear(dump, { native })):toBe(false)
		element.interactive = false
		t:expect(RaceSpace.centerClear(dump)):toBe(true)
		element.rect.y = 410
		t:expect(RaceSpace.centerClear(dump)):toBe(false)
		element.rect = { x = 20, y = 650, width = 100, height = 44 }
		local measuredThumb: RaceSpace.TouchRect = { x = 0, y = 620, width = 150, height = 224 }
		t:expect(RaceSpace.touchControlsClear(dump, { measuredThumb })):toBe(true)
		element.interactive = true
		t:expect(RaceSpace.touchControlsClear(dump, { measuredThumb })):toBe(false)
		element.interactive = false
		element.active = true
		t:expect(RaceSpace.touchControlsClear(dump, { measuredThumb })):toBe(false)
		element.scrollClip = { x = 200, y = 650, width = 100, height = 44 }
		t:expect(RaceSpace.touchControlsClear(dump, { measuredThumb })):toBe(true)
		element.scrollClip = nil
		element.visible = false
		t:expect(RaceSpace.touchControlsClear(dump, { measuredThumb })):toBe(true)
		element.visible = true
		element.rect = { x = 16, y = 48, width = 160, height = 44 }
		element.text = {
			content = "Coins\nGems",
			size = 18,
			bounds = { width = 80, height = 44 },
			scaled = false,
			wrapped = true,
			bold = false,
			color = { r = 1, g = 1, b = 1 },
			transparency = 0,
		}
		local roster = table.clone(element)
		roster.index = 2
		roster.root = 2
		roster.path = "AnotherScreen.Roster"
		roster.rect = { x = 16, y = 20, width = 160, height = 24 }
		dump.elements[2] = roster
		t:expect(RaceSpace.textClear(dump)):toBeTrueWith("stacked HUD readouts clear each other across screens")
		roster.rect.y = 60
		t:expect(not RaceSpace.textClear(dump)):toBeTrueWith("the old roster position intersects the wallet")
		roster.rect.y = 91
		t:expect(RaceSpace.textClear(dump)):toBeTrueWith("one pixel of edge rounding is allowed")
		roster.rect.y = 90
		t:expect(not RaceSpace.textClear(dump)):toBeTrueWith("two pixels of text overlap is rejected")
		roster.rect = { x = 16, y = 48, width = 160, height = 44 }
		t:expect(not RaceSpace.textClear(dump)):toBeTrueWith("fully coincident text is an overlap")
		roster.visible = false
		t:expect(RaceSpace.textClear(dump)):toBe(true)
		roster.visible = true
		roster.scrollClip = { x = 16, y = 0, width = 160, height = 44 }
		t:expect(RaceSpace.textClear(dump)):toBeTrueWith("clipped text does not collide")
		roster.scrollClip = nil
		local invisibleText = table.clone(element.text :: Audit.Text)
		invisibleText.transparency = 1
		roster.text = invisibleText
		t:expect(RaceSpace.textClear(dump)):toBe(true)
		local aligned = table.clone(element.text :: Audit.Text)
		aligned.xAlignment, aligned.yAlignment = "Left", "Center"
		aligned.bounds = { width = 40, height = 18 }
		element.text = aligned
		local rosterText = table.clone(aligned)
		roster.text = rosterText
		rosterText.xAlignment = "Right"
		t:expect(RaceSpace.textClear(dump)):toBeTrueWith("overlapping label boxes can contain separate rendered text")
		rosterText.xAlignment = "Left"
		t:expect(RaceSpace.textClear(dump)):toBe(false)
		dump.roots = {
			{
				index = 1,
				class = "ScreenGui",
				path = "Hub",
				enabled = true,
				displayOrder = 0,
				world = false,
				rect = element.rect,
			},
			{
				index = 2,
				class = "ScreenGui",
				path = "Modal",
				enabled = true,
				displayOrder = 2,
				world = false,
				rect = element.rect,
			},
		}
		roster.background = { color = { r = 0, g = 0, b = 0 }, transparency = 0 }
		t:expect(RaceSpace.textClear(dump)):toBeTrueWith("opaque modal paint covers text on lower screen layers")
		roster.background.transparency = 1
		t:expect(RaceSpace.textClear(dump)):toBe(false)
		dump.roots = {}
		for _, size in { { 1920, 1080, 0 }, { 390, 844, 0 }, { 844, 390, 59 }, { 1180, 820, 0 }, { 1920, 1080, 0 } } do
			dump.screen.width, dump.screen.height = size[1], size[2]
			dump.screen.guiInset.top = 58
			dump.screen.safeArea = { x = size[3], y = 0, width = size[1] - size[3], height = size[2] - 20 }
			dump.elements = { element }
			element.rect = { x = size[3] + 16, y = 74, width = 100, height = 44 }
			t:expect(RaceSpace.safeContent(dump))
				:toBeTrueWith("safe HUD content clears the core UI and the device cutout")
			element.rect.y = 56
			t:expect(RaceSpace.safeContent(dump)):toBe(false)
			element.rect.y = 57
			t:expect(RaceSpace.safeContent(dump)):toBeTrueWith("safe content allows one pixel of rounding")
			if size[3] > 0 then
				element.rect.x = 0
				t:expect(RaceSpace.safeContent(dump)):toBe(false)
			end
			element.rect = { x = size[3] + 16, y = 74, width = 100, height = 44 }
			local action = table.clone(element)
			action.text = nil
			action.interactive = true
			action.selectable = false
			action.rect = { x = size[3] + 16, y = 0, width = 44, height = 44 }
			dump.elements = { action }
			t:expect(not RaceSpace.safeContent(dump)):toBeTrueWith("unlabelled actions also clear the core UI")
			dump.screen.topbarSafeArea = { x = size[3] + 164, y = 0, width = size[1] - size[3] - 164, height = 58 }
			t:expect(not RaceSpace.safeContent(dump)):toBeTrueWith("an action over the core buttons stays unsafe")
			action.rect = { x = size[1] - 60, y = 7, width = 44, height = 44 }
			t:expect(RaceSpace.safeContent(dump)):toBeTrueWith("an action inside the free top-bar strip is safe")
			action.rect = { x = size[1] - 60, y = 7, width = 44, height = 70 }
			t:expect(not RaceSpace.safeContent(dump)):toBeTrueWith("an action across the top-bar edge is unsafe")
			dump.screen.topbarSafeArea = nil
			dump.elements = { element }
			element.interactive = true
			element.selectable = true
			(element.text :: Audit.Text).content = "Close"
			local scrim = table.clone(element)
			scrim.index = 2
			scrim.text = nil
			scrim.interactive = false
			scrim.selectable = false
			scrim.background = { color = { r = 0.02, g = 0.03, b = 0.05 }, transparency = 0.35 }
			scrim.rect = { x = 0, y = 0, width = size[1], height = size[2] }
			dump.elements[2] = scrim
			t:expect(RaceSpace.scrimCovers(dump)):toBeTrueWith("the strong full-screen scrim covers the viewport")
			scrim.rect = { x = size[3], y = 58, width = size[1] - size[3], height = size[2] - 58 }
			t:expect(not RaceSpace.scrimCovers(dump))
				:toBeTrueWith("the weak safe-area scrim leaves the top bar undimmed")
			dump.selected = 1
			t:expect(RaceSpace.selectionValid(dump)):toBe(true)
			element.visible = false
			t:expect(RaceSpace.selectionValid(dump)):toBe(false)
			element.visible = true
			dump.selected = nil
		end
	end)
end
