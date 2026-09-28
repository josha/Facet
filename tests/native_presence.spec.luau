--!strict
local t = require("./lib/testkit")
local fadeKit = require("./lib/fade")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")

local function dialog(shown: any, options: any?): any
	return overlay.new(function(UI, Host)
		return UI.Dialog "D" {
			isPresented = shown,
			onPresentedChange = function(value: boolean)
				shown:set(value)
			end,
			title = "Quit race?",
			content = function()
				return Host.TextLabel "Body" { Text = "Progress is lost." }
			end,
		}
	end, options)
end

t.describe("presence: opacity leads travel", function()
	t.it("a dialog is opaque at 60 percent of its travel and clear at half of its exit", function()
		local shown = Compose.cell(true)
		local w = dialog(shown)
		local panel = w.find("Panel")
		local scale = panel:FindFirstChildWhichIsA("UIScale", true)
		local sawOpaqueEarly = false
		for _ = 1, 30 do
			w.advance(1 / 60)
			if fadeKit.of(panel) == 0 and scale.Scale < 1 then
				sawOpaqueEarly = true
			end
		end
		t.expect(sawOpaqueEarly).toBe(true)
		shown:set(false)
		local sawClearEarly = false
		for _ = 1, 30 do
			w.advance(1 / 60)
			if panel.Parent and fadeKit.of(panel) == 1 and scale.Scale > 0.94 then
				sawClearEarly = true
			end
		end
		t.expect(sawClearEarly).toBe(true)
		w.stop()
	end)
end)

t.describe("presence: motion level limited cross-fades", function()
	t.it("under limited a dialog never scales and fades in and out over motion.reducedFade", function()
		local shown = Compose.cell(true)
		local w = dialog(shown, { motionLevel = "limited" })
		local panel = w.find("Panel")
		local scale = panel:FindFirstChildWhichIsA("UIScale", true)
		t.expect(scale.Scale).toBe(1)
		t.expect(fadeKit.of(panel) > 0).toBe(true)
		w.advance(1 / 60)
		t.expect(scale.Scale).toBe(1)
		t.expect(fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1).toBe(true)
		w.advance(0.2, 12)
		t.expect(fadeKit.of(panel)).toBe(0)
		shown:set(false)
		w.advance(1 / 60)
		t.expect(panel.Parent ~= nil).toBe(true)
		t.expect(scale.Scale).toBe(1)
		t.expect(fadeKit.of(panel) > 0).toBe(true)
		w.advance(0.2, 12)
		t.expect(w.find("Panel")).toBeNil()
		w.stop()
	end)

	t.it("under none a dialog is whole on its first frame and leaves at once", function()
		local shown = Compose.cell(true)
		local w = dialog(shown, { motionLevel = "none" })
		local panel = w.find("Panel")
		t.expect(panel:FindFirstChildWhichIsA("UIScale", true).Scale).toBe(1)
		t.expect(fadeKit.of(panel)).toBe(0)
		shown:set(false)
		w.advance(1 / 60)
		t.expect(w.find("Panel")).toBeNil()
		w.stop()
	end)

	t.it("under limited a sheet never slides and its panel fades in over motion.reducedFade", function()
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return UI.Sheet "S" {
				isPresented = shown,
				detent = Compose.cell("medium"),
				title = "Race details",
				content = function()
					return Host.TextLabel "Copy" { Text = "Lap times" }
				end,
			}
		end, { motionLevel = "limited" })
		w.find("Modal").AbsoluteSize = w.Vector2.new(800, 600)
		local panel = w.find("SheetPanel")
		local at = nil
		local sawFading = false
		for _ = 1, 12 do
			w.advance(1 / 60)
			local fade = fadeKit.of(panel)
			if fade < 1 then
				at = at or panel.Position
				t.expect(panel.Position).toBe(at)
			end
			sawFading = sawFading or (fade > 0 and fade < 1)
		end
		t.expect(at and at.Y.Offset).toBe(0)
		t.expect(sawFading).toBe(true)
		t.expect(fadeKit.of(panel)).toBe(0)
		w.stop()
	end)
end)

t.describe("presence: limited cross-fades the toast, tabs, stack and disclosure", function()
	local LIMITED = { motionLevel = "limited" }

	local function fadesOver(w: any, node: any, from: number, to: number): number
		local frames = 0
		while fadeKit.of(node) ~= to and frames < 30 do
			w.advance(1 / 60)
			frames += 1
			local value = fadeKit.of(node)
			t.expect(if from > to then value <= from else value >= from).toBe(true)
		end
		t.expect(fadeKit.of(node)).toBe(to)
		return frames
	end

	t.it("a toast row fades in over reducedFade and never moves", function()
		local shown = Compose.cell(false)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				Compose.show(function(use)
					return use(shown)
				end, function()
					return UI.Toast "T" { message = "Saved" }
				end),
			})
		end, LIMITED)
		shown:set(true)
		local row = w.find("ToastRow")
		local at = row.Position
		t.expect(fadeKit.of(row) > 0).toBe(true)
		local frames = fadesOver(w, row, 1, 0)
		t.expect(frames >= 6 and frames <= 12).toBe(true)
		t.expect(row.Position).toBe(at)
		w.stop()
	end)

	t.it("a TabView page fades in over reducedFade", function()
		local selected = Compose.cell("one")
		local w = overlay.new(function(UI, Host)
			return UI.TabView {
				selection = selected,
				tabs = {
					{ id = "one", label = "One", content = Host.Frame "PageOne" {} },
					{ id = "two", label = "Two", content = Host.Frame "PageTwo" {} },
				},
			}
		end, LIMITED)
		w.advance(0.5, 30)
		selected:set("two")
		local page = w.find("PageTwo")
		while page and page:FindFirstChild("FadePaint") == nil do
			page = page.Parent
		end
		local frames = fadesOver(w, page, 1, 0)
		t.expect(frames >= 6 and frames <= 12).toBe(true)
		w.stop()
	end)

	t.it("a NavigationStack push has no travel and the new page fades in over reducedFade", function()
		local path = Compose.cell({})
		local w = overlay.new(function(UI, Host)
			return UI.NavigationStack {
				path = path,
				root = { title = "Root", content = Host.Frame "RootBody" {} },
				destinations = { detail = { title = "Detail", content = Host.Frame "DetailBody" {} } },
			}
		end, LIMITED)
		w.advance(0.5, 30)
		path:set({ { id = "detail" } })
		local page = w.find("detail")
		t.expect(page.Position.X.Scale).toBe(0)
		local frames = fadesOver(w, page, 1, 0)
		t.expect(frames >= 6 and frames <= 12).toBe(true)
		t.expect(page.Position.X.Scale).toBe(0)
		w.stop()
	end)

	t.it("a DisclosureGroup's height lands at once and its content fades over reducedFade", function()
		local expanded = Compose.cell(false)
		local w = overlay.new(function(UI)
			return UI.DisclosureGroup "Settings" {
				label = "Appearance",
				expanded = expanded,
				content = function()
					return UI.Button "Palette" { label = "Palette" }
				end,
			}
		end, LIMITED)
		expanded:set(true)
		local reveal, fade = w.find("Reveal"), w.find("RevealFade")
		fade.AbsoluteSize = w.Vector2.new(300, 120)
		w.advance(1 / 60)
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		local frames = fadesOver(w, fade, 1, 0)
		t.expect(frames >= 5 and frames <= 12).toBe(true)
		w.stop()
	end)
end)
