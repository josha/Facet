--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engines = require("./lib/native_engine")
local Vector2 = require("@lune/roblox").Vector2
local Compose = Facet.Compose
local themes = Facet.themes
local expect = t.expect

local function find(root: any, name: string): any
	if root == nil then
		return nil
	end
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function world(build: (any, any, any) -> any, options: { [string]: any }?): any
	local o: { [string]: any } = options or {}
	local engine: any = engines.new({
		measureText = function(node: any): any
			local text = node.Text or ""
			return Vector2.new(#text * 11, if #text > 0 then 20 else 0)
		end,
	})
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local UI: any = Facet.controls(
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			theme = o.theme,
		} :: any
	)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors, engine) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		screen = screen,
		UI = UI,
		step = function(count: number?)
			for _ = 1, count or 1 do
				engine.heartbeat.fire(1 / 60)
			end
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function sheetFor(w: any, package: any): any
	local _, sheet = w.runtime.mount(function()
		return themes.createStyleSheet(
			w.runtime,
			package,
			{
				types = w.engine.types,
				preferredTransparency = 1,
				reducedMotion = false,
			} :: any
		)
	end, w.engine.new("Folder"))
	return sheet
end

local function rule(sheet: any, selector: string): any
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			return node
		end
	end
	return nil
end

t.describe("Toggle switch follows controlSize", function()
	t.it("each rung draws its own track and knob; no rung keeps the 38 by 24 switch", function()
		local rung = Compose.cell("compact")
		local w = world(function(UI)
			return UI.VStack {
				UI.Toggle "Plain" { value = Compose.cell(true), label = "Sound" },
				UI.Toggle "Sized" { value = Compose.cell(true), label = "Music", controlSize = rung },
			}
		end)
		local plain = find(find(w.screen, "Plain"), "Indicator")
		expect(plain.Size.X.Offset .. "x" .. plain.Size.Y.Offset).toBe("38x24")
		local indicator = find(find(w.screen, "Sized"), "Indicator")
		local mark = find(indicator, "Mark")
		expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset).toBe("32x20")
		expect(mark.Size.X.Offset).toBe(14)
		expect(indicator.Position.X.Offset).toBe(-40)
		rung:set("large")
		w.step()
		expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset).toBe("44x28")
		expect(mark.Size.X.Offset).toBe(22)
		expect(find(indicator, "UICorner").CornerRadius.Offset).toBe(14)
		rung:set("regular")
		w.step()
		expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset).toBe("38x24")
		w.stop()
	end)
end)

t.describe("voice and contrast statuses", function()
	t.it("StatusIndicator and Badge take voice and contrast; voice defaults between warning and danger", function()
		local status = Compose.cell("voice")
		local w = world(function(UI)
			return UI.VStack {
				UI.StatusIndicator "Dot" { status = status },
				UI.Badge "Tag" { label = "Live", status = "contrast" },
			}
		end)
		local dot = find(w.screen, "Dot")
		expect(dot:HasTag("facet-status-voice")).toBe(true)
		status:set("contrast")
		expect(dot:HasTag("facet-status-contrast")).toBe(true)
		expect(dot:HasTag("facet-status-voice")).toBe(false)
		expect(find(w.screen, "Tag"):HasTag("facet-status-contrast")).toBe(true)
		local package = themes.neutralPackage()
		local sheet = sheetFor(w, package)
		local colors = package.style.themes[1].colors
		local warning, danger = colors.warning :: any, colors.danger :: any
		local voice = rule(sheet, ".facet-status-voice"):GetProperties().BackgroundColor3
		expect(math.abs(voice.R - (warning.r + danger.r) / 2) < 1e-6).toBe(true)
		expect(math.abs(voice.G - (warning.g + danger.g) / 2) < 1e-6).toBe(true)
		local strong = colors.contentStrong :: any
		local contrast = rule(sheet, ".facet-status-contrast"):GetProperties().BackgroundColor3
		expect(math.abs(contrast.R - strong.r) < 1e-6).toBe(true)
		package.style.themes[1].extra.voice = { r = 0.1, g = 0.2, b = 0.3 }
		local authored = rule(sheetFor(w, package), ".facet-status-voice"):GetProperties().BackgroundColor3
		expect(math.abs(authored.B - 0.3) < 1e-6).toBe(true)
		w.stop()
	end)
end)
