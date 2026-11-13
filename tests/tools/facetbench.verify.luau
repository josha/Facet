--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Audit = require("../../tools/vendor/verify/src/roblox/ui-audit")
local RaceSpace = require("../../tools/play/host/space")
local Play = require("../../tools/play/host/play")
local Setup = require("../../tools/facet/lib/facetbench_setup")
local Json = require("../../tools/facet/lib/json")
local Files = require("../../tools/facet/lib/files")
local Admission = require("../../eval/admission")
local Preflight = require("../../eval/preflight")
local Submission = require("../../eval/submission")

local function screenDump(width: number, height: number): (Audit.Dump, (Audit.Element) -> Audit.Element)
	local dump: Audit.Dump = {
		schemaVersion = 1,
		screen = {
			width = width,
			height = height,
			scale = 1,
			guiInset = { left = 0, top = 0, right = 0, bottom = 0 },
			input = { "touch" },
		},
		roots = {
			{
				index = 1,
				class = "ScreenGui",
				path = "PlayerGui.Game",
				enabled = true,
				displayOrder = 0,
				world = false,
				rect = { x = 0, y = 0, width = width, height = height },
			},
		},
		elements = {},
		instances = 1,
		truncated = false,
	}
	local function add(element: Audit.Element): Audit.Element
		element.index = #dump.elements + 1
		element.order = element.index
		table.insert(dump.elements, element)
		return element
	end
	return dump, add
end

local function part(path: string, rect: { number }, parent: number?): Audit.Element
	return {
		index = 0,
		parent = parent,
		root = 1,
		class = "Frame",
		path = path,
		rect = { x = rect[1], y = rect[2], width = rect[3], height = rect[4] },
		rotation = 0,
		visible = true,
		zIndex = 1,
		order = 0,
		interactive = false,
		selectable = false,
		active = false,
		interactable = true,
		next = {},
		selectionGroup = false,
		stops = {},
		background = { color = { r = 0, g = 0, b = 0 }, transparency = 1 },
	}
end

local function words(element: Audit.Element, content: string): Audit.Element
	element.class = "TextLabel"
	element.text = {
		content = content,
		size = 18,
		bounds = { width = element.rect.width, height = element.rect.height },
		scaled = false,
		wrapped = false,
		bold = false,
		color = { r = 1, g = 1, b = 1 },
		transparency = 0,
	}
	return element
end

local function button(element: Audit.Element, content: string): Audit.Element
	words(element, content)
	element.class = "TextButton"
	element.interactive = true
	element.active = true
	return element
end

return function(harness: Verify.Harness)
	harness:case("a capture is admitted to the comparison only when its dump shows the requested state", function(t)
		local function race(menu: boolean): Audit.Dump
			local dump, add = screenDump(844, 390)
			local hud = add(part("Game.HUD", { 0, 0, 844, 390 }))
			add(words(part("Game.HUD.Lap", { 20, 20, 120, 40 }, hud.index), "Lap 2 of 3"))
			add(button(part("Game.HUD.Pit", { 700, 320, 120, 44 }, hud.index), "Pit"))
			if menu then
				local layer = add(part("Game.Menu", { 0, 0, 844, 390 }))
				layer.background.transparency = 0.4
				add(button(part("Game.Menu.Tires", { 300, 150, 240, 44 }, layer.index), "Change tires"))
			end
			return dump
		end
		local function tutorial(expanded: boolean): Audit.Dump
			local dump, add = screenDump(390, 844)
			local hud = add(part("Game.HUD", { 0, 0, 390, 844 }))
			add(button(part("Game.HUD.Help", { 140, 20, 110, 44 }, hud.index), "First race help"))
			if expanded then
				local plate = add(part("Game.Lesson", { 55, 80, 280, 220 }))
				plate.background.transparency = 0
				add(words(part("Game.Lesson.Title", { 70, 95, 250, 30 }, plate.index), "Prepare your kart"))
				add(button(part("Game.Lesson.Next", { 200, 240, 120, 44 }, plate.index), "Next"))
			end
			return dump
		end
		local dumps: { [string]: Audit.Dump } = {
			["race-open.json"] = race(false),
			["race-menu.json"] = race(true),
			["lesson.json"] = tutorial(true),
			["launcher.json"] = tutorial(false),
		}
		local function load(path: string): Audit.Dump?
			return assert(dumps[path], "no dump " .. path)
		end
		local lap: Admission.Expectation = { visible = { "lap" } }
		local lesson: Admission.Expectation = { visible = { "Prepare your kart", "Next" } }
		local review = Admission.review({
			{
				id = "a-race-1",
				arm = "plain",
				device = "phone-landscape",
				screen = "race",
				image = "a.png",
				dump = "race-menu.json",
				expect = lap,
			},
			{
				id = "a-race-2",
				arm = "plain",
				device = "phone-landscape",
				screen = "race",
				image = "a2.png",
				dump = "race-open.json",
				attempt = 2,
				expect = lap,
			},
			{
				id = "b-race-1",
				arm = "facet",
				device = "phone-landscape",
				screen = "race",
				image = "b.png",
				dump = "race-open.json",
				expect = lap,
			},
			{
				id = "a-help-1",
				arm = "plain",
				device = "phone-portrait",
				screen = "tutorial",
				image = "c.png",
				dump = "lesson.json",
				expect = lesson,
			},
			{
				id = "b-help-1",
				arm = "facet",
				device = "phone-portrait",
				screen = "tutorial",
				image = "d.png",
				dump = "launcher.json",
				expect = lesson,
			},
			{
				id = "b-shop-1",
				arm = "facet",
				device = "desktop",
				screen = "shop",
				image = "e.png",
				expect = { visible = { "Shop" } },
			},
			{
				id = "b-hub-1",
				arm = "facet",
				device = "desktop",
				screen = "hub",
				image = "f.png",
				dump = "race-open.json",
			},
			{
				id = "b-lobby-1",
				arm = "facet",
				device = "desktop",
				screen = "lobby",
				image = "g.png",
				dump = "race-open.json",
			},
		}, load, { "plain", "facet" })
		local byId: { [string]: Admission.Decision } = {}
		for _, decision in review.decisions do
			byId[decision.id] = decision
		end
		t:expect(#review.decisions):toBe(8)
		t:expect(byId["a-race-1"].admitted):toBe(false)
		t:expect(byId["a-race-1"].reasons[1]):toBe("a layer covers the controls of the screen: Game.Menu")
		t:expect(byId["a-race-2"].admitted):toBe(true)
		t:expect(byId["b-race-1"].admitted):toBe(true)
		t:expect(byId["a-help-1"].admitted):toBe(true)
		t:expect(byId["b-help-1"].admitted):toBe(false)
		t:expect(table.concat(byId["b-help-1"].reasons, "; "))
			:toBe('the expected text "Prepare your kart" is not visible; the expected text "Next" is not visible')
		t:expect(byId["b-shop-1"].reasons[1])
			:toBe("no interface dump was saved with the capture, so its state cannot be checked")
		t:expect(byId["b-hub-1"].reasons[1]):toBe("the evaluator named 0 text(s) that show this state; hub needs 1")
		t:expect(byId["b-lobby-1"].reasons[1]):toBe("lobby is not a screen of the matched comparison")
		local pairs: { [string]: Admission.Pair } = {}
		for _, pair in review.pairs do
			pairs[pair.device .. "/" .. pair.screen] = pair
		end
		t:expect(pairs["phone-landscape/race"].admitted):toBe(true)
		t:expect(pairs["phone-landscape/race"].captures.plain):toBe("a-race-2")
		t:expect(pairs["phone-portrait/tutorial"].admitted):toBe(false)
		t:expect(pairs["phone-portrait/tutorial"].reason)
			:toBe("no admitted capture for facet; the pair is not compared")
		local any: Admission.Expectation = { visible = { "lap" }, modal = "any" }
		t:expect(#Admission.check({
			id = "x",
			arm = "plain",
			device = "phone-landscape",
			screen = "race",
			image = "x.png",
			expect = any,
		}, race(true))):toBe(0)
		local touch = race(false)
		table.insert(touch.roots, {
			index = 2,
			class = "ScreenGui",
			path = "PlayerGui.TouchGui",
			enabled = true,
			displayOrder = -1,
			world = false,
			rect = { x = 0, y = 0, width = 844, height = 390 },
		})
		local jump = button(part("TouchGui.Jump", { 740, 250, 70, 70 }), "")
		jump.root = 2
		jump.index = #touch.elements + 1
		table.insert(touch.elements, jump)
		touch.elements[1].background.transparency = 0
		t:expect(Admission.modal(touch)):toBe(nil)
	end)

	harness:case(
		"an author with images needs a generated file and an upload through its own tools before the clock",
		function(t)
			local required = { Preflight.GENERATION, Preflight.UPLOAD }
			local function outcome(record: Preflight.Record?): { [string]: string }
				local report = Verify.runCases(Preflight.cases(record, required), { executor = "test" }, os.clock)
				local found: { [string]: string } = {}
				for _, result in report.results do
					found[result.id] = result.status
				end
				return found
			end
			local scoped: Preflight.Record = {
				agent = "codex-sol-images",
				tools = { "start_stop_play", "screen_capture", "execute_luau", "get_console_output", "input" },
				generation = { ok = true, file = "concept.png", bytes = 4096, at = 100 },
				upload = { ok = true, tool = "upload_image", assetId = "123", loaded = true, at = 120 },
				authorStart = 200,
			}
			local missing = outcome(scoped)
			t:expect(missing["preflight/image-generation"]):toBe("passed")
			t:expect(missing["preflight/asset-upload"]):toBe("failed")
			t:expect(Preflight.upload(scoped)[1]):toBe(
				"the author's Studio tools have no upload route; they need upload_image or open_cloud_invoke. Tools: start_stop_play, screen_capture, execute_luau, get_console_output, input"
			)
			table.insert(scoped.tools, "upload_image")
			local ready = outcome(scoped)
			t:expect(ready["preflight/asset-upload"]):toBe("passed")
			t:expect(ready["preflight/before-clock"]):toBe("passed")
			scoped.authorStart = 110
			t:expect(outcome(scoped)["preflight/before-clock"]):toBe("failed")
			scoped.authorStart = nil
			(scoped.upload :: Preflight.Upload).loaded = false
			t:expect(outcome(scoped)["preflight/asset-upload"]):toBe("failed")
			t:expect(outcome(nil)["preflight/image-generation"]):toBe("failed")
			t:expect(Preflight.generates("codex", { "--disable", "shell_tool" })):toBe(true)
			t:expect(Preflight.generates("codex", { "--disable", "image_generation" })):toBe(false)
			t:expect(Preflight.generates("claude-code", { "--tools=" })):toBe(false)
			local none = Verify.runCases(Preflight.cases(nil, {}), { executor = "test" }, os.clock)
			t:expect(none.passed):toBe(1)
		end
	)

	harness:case("a submission seals once, reopens unchanged and fails when its bytes change", function(t)
		local directory = Files.temporaryDirectory("facetbench-seal-")
		local place = Files.join(directory, "agent.rbxlx")
		Files.write(place, '<roblox version="4"><Item class="Workspace"></Item></roblox>')
		local evidence = Files.join(directory, "evidence")
		local sealed = Submission.capture(place, Files.join(evidence, "submission"), "seal-test")
		t:expect(sealed.passed):toBe(1)
		t:expect(Files.isFile(Files.join(evidence, "submission", "game.rbxl"))):toBe(true)
		local reopened = Submission.seal(evidence, "seal-test")
		t:expect(reopened.passed):toBe(1)
		local evaluated = Submission.validate(nil, Files.join(evidence, "submission"))
		t:expect(evaluated.passed):toBe(1)
		Files.write(place, '<roblox version="4"><Item class="Workspace"><Item class="Part"></Item></Item></roblox>')
		t:expect(Submission.validate(place, Files.join(evidence, "submission")).passed):toBe(0)
		Files.write(Files.join(evidence, "submission", "game.rbxl"), "<roblox!changed")
		t:expect(Submission.validate(nil, Files.join(evidence, "submission")).passed):toBe(0)
		Files.remove(directory)
	end)

	harness:case("the kept Studio place is saved with the tools of its platform", function(t)
		local mac = Submission.saveCommand("macos", "/Users/a b/agent.rbxlx", 4725)
		t:expect(mac[1]):toBe("/bin/sh")
		t:expect(mac[5]):toBe("/Users/a b/agent.rbxlx")
		t:expect(mac[6]):toBe("4725")
		t:expect(string.find(mac[3], 'keystroke "s" using command down', 1, true) ~= nil):toBe(true)
		t:expect(string.find(mac[3], "whose unix id is", 1, true) ~= nil):toBe(true)
		t:expect(string.find(mac[3], "powershell", 1, true) == nil):toBe(true)
		local windows = Submission.saveCommand("windows", "C:/runs/agent.rbxlx", 12)
		t:expect(windows[1]):toBe("powershell")
		local ok, message = pcall(Submission.saveCommand, "other" :: Submission.Platform, "/tmp/agent.rbxlx", 1)
		t:expect(ok):toBe(false)
		t:expect(string.find(tostring(message), "facetbench snapshot --place", 1, true) ~= nil):toBe(true)
	end)

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
