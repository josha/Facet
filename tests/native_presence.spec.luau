--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local NavigationFixtures = require("../src/ui/navigation_types")
local FixtureNavigationTypes = require("../src/ui/navigation_types")
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local t = require("./lib/testkit")
local materialize = require("./lib/materialize")
local fadeKit = require("./lib/fade")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")

local function dialog(shown: any, options: any?, unsized: boolean?): any
	local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
		return UI.Dialog "D" {
			isPresented = shown,
			onPresentedChange = function(value: boolean)
				shown:set(value)
			end,
			title = "Quit race?",
			content = function(): Instance
				return Host.TextLabel "Body" { Text = "Progress is lost." }
			end,
		}
	end, options)
	local panel = w.find("Panel")
	if panel and not unsized then
		panel.AbsoluteSize = w.Vector2.new(560, 441)
	end
	return w
end

t.describe("presence: opacity leads travel", function()
	t.it("a dialog is opaque at 60 percent of its travel and clear at half of its exit", function()
		local shown = Compose.cell(true)
		local w = dialog(shown)
		local panel = w.find("Panel")
		local scale = materialize.of(panel)
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

t.describe("presence: the fades take their share of the time, not of the eased travel", function()
	t.it("a dialog fades in over several frames and is opaque while it still scales", function()
		local shown = Compose.cell(true)
		local w = dialog(shown)
		local panel = w.find("Panel")
		local scale = materialize.of(panel)
		local partial, elapsed = 0, 0
		while fadeKit.of(panel) > 0 and elapsed < 1 do
			w.advance(1 / 120)
			elapsed += 1 / 120
			if fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1 then
				partial += 1
			end
		end
		t.expect(partial >= 10).toBe(true)
		t.expect(scale.Scale < 1).toBe(true)
		w.stop()
	end)

	t.it("a dialog fades out over several frames, not the first eased step", function()
		local shown = Compose.cell(true)
		local w = dialog(shown)
		local panel = w.find("Panel")
		w.advance(0.3, 18)
		shown:set(false)
		local partial, elapsed = 0, 0
		while panel.Parent and fadeKit.of(panel) < 1 and elapsed < 1 do
			w.advance(1 / 120)
			elapsed += 1 / 120
			if fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1 then
				partial += 1
			end
		end
		t.expect(partial >= 6).toBe(true)
		t.expect(elapsed >= 0.06 and elapsed <= 0.09).toBe(true)
		w.stop()
	end)
end)

t.describe("presence: motion level limited cross-fades", function()
	t.it("under limited a dialog never scales and fades in and out over motion.reducedFade", function()
		local shown = Compose.cell(true)
		local w = dialog(shown, { motionLevel = "limited" })
		local panel = w.find("Panel")
		local scale = materialize.of(panel)
		t.expect(scale.Scale).toBe(1)
		t.expect(fadeKit.of(panel) > 0).toBe(true)
		w.advance(1 / 60, 3)
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

	t.it("under none a dialog is whole once its size has held and leaves at once", function()
		local shown = Compose.cell(true)
		local w = dialog(shown, { motionLevel = "none" })
		local panel = w.find("Panel")
		w.advance(1 / 60, 2)
		t.expect(materialize.of(panel).Scale).toBe(1)
		t.expect(fadeKit.of(panel)).toBe(0)
		shown:set(false)
		w.advance(1 / 60)
		t.expect(w.find("Panel")).toBeNil()
		w.stop()
	end)

	t.it("under limited a sheet never slides and its panel fades in over motion.reducedFade", function()
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			return UI.Sheet "S" {
				isPresented = shown,
				detent = Compose.cell("medium"),
				title = "Race details",
				content = function(): Instance
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
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				Name = "S",
				Compose.show(function(use: Use)
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
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			return UI.TabView {
				selection = selected,
				tabs = {
					{ id = "one", label = "One", content = Host.Frame "PageOne" {} } :: FixtureNavigationTypes.Tab,
					{ id = "two", label = "Two", content = Host.Frame "PageTwo" {} } :: FixtureNavigationTypes.Tab,
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
		local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			return UI.NavigationStack {
				path = path,
				root = { title = "Root", content = Host.Frame "RootBody" {} } :: NavigationFixtures.NavigationDestination<any>,
				destinations = {
					detail = { title = "Detail", content = Host.Frame "DetailBody" {} } :: NavigationFixtures.NavigationDestination<any>,
				},
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
		local w = overlay.new(function(UI: FacetControls)
			return UI.DisclosureGroup "Settings" {
				label = "Appearance",
				expanded = expanded,
				content = function(): Instance
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

t.describe("presence: a Dialog is measured at rest", function()
	for _, level in { "normal", "none" } do
		t.it(`a Dialog waits for its size to hold, then never grows after it shows ({level})`, function()
			local shown = Compose.cell(true)
			local w = dialog(shown, { motionLevel = level }, true)
			local panel = w.find("Panel")
			local scale = materialize.of(panel)
			panel.AbsoluteSize = w.Vector2.new(560, 420)
			w.advance(1 / 60)
			t.expect(fadeKit.of(panel)).toBe(1)
			t.expect(scale.Scale).toBe(1)
			panel.AbsoluteSize = w.Vector2.new(560, 441)
			w.advance(1 / 60)
			t.expect(fadeKit.of(panel)).toBe(1)
			local seen = false
			for _ = 1, 30 do
				w.advance(1 / 60)
				if fadeKit.of(panel) < 1 then
					seen = true
					if scale.Scale < 1 then
						t.expect(panel.AutomaticSize).toBe(w.Enum.AutomaticSize.None)
						t.expect(panel.Size.Y.Offset).toBeCloseTo(441 * scale.Scale, 1)
					end
				end
			end
			t.expect(seen).toBe(true)
			t.expect(panel.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
			w.stop()
		end)
	end
end)

t.describe("presence: an interrupt keeps the opacity continuous", function()
	t.it("reversing mid-entrance and mid-exit never steps the fade", function()
		local shown = Compose.cell(true)
		local w = dialog(shown)
		local panel = w.find("Panel")
		w.advance(1 / 60, 4)
		local before = fadeKit.of(panel)
		t.expect(before > 0 and before < 1).toBe(true)
		shown:set(false)
		t.expect(fadeKit.of(panel)).toBeCloseTo(before, 1e-4)
		w.advance(1 / 60)
		local leaving = fadeKit.of(panel)
		t.expect(leaving >= before).toBe(true)
		shown:set(true)
		t.expect(fadeKit.of(panel)).toBeCloseTo(leaving, 1e-4)
		w.advance(0.3, 18)
		t.expect(fadeKit.of(panel)).toBe(0)
		w.stop()
	end)
end)
