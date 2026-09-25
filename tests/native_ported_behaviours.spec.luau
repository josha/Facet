--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engines = require("./lib/native_engine")
local Roblox = require("@lune/roblox")
local Vector2, UDim2 = Roblox.Vector2, Roblox.UDim2
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

t.describe("Avatar faces, in-experience ring and background", function()
	t.it("an icon face replaces the initials, also for a group member", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.Avatar "Guest" { name = "Guest Player", icon = "person" },
				UI.AvatarGroup "Group" { items = { { id = "g", name = "Guest", icon = "person" } } },
			}
		end)
		local guest = find(w.screen, "Guest")
		expect(find(guest, "Face") ~= nil).toBe(true)
		expect(find(guest, "Initials").Visible).toBe(false)
		local member = find(find(w.screen, "Group"), "g")
		expect(find(member, "Face") ~= nil).toBe(true)
		expect(find(member, "Initials").Visible).toBe(false)
		expect(function()
			w.UI.Avatar { name = "A", icon = "person", image = "rbxassetid://1" }
		end).toThrow()
		w.stop()
	end)

	t.it("inExperience rings the face in accent with a surface gap and no corner mark", function()
		local presence = Compose.cell("inExperience")
		local w = world(function(UI)
			return UI.Avatar "A" { name = "Ada", presence = presence, background = "success" }
		end)
		local avatar = find(w.screen, "A")
		local ring = find(avatar, "PresenceRing")
		expect(ring.Visible).toBe(true)
		expect(ring:HasTag("facet-avatar-ring")).toBe(true)
		expect(find(ring, "Gap"):HasTag("facet-avatar-ring-gap")).toBe(true)
		expect(find(avatar, "Presence").Visible).toBe(false)
		expect(avatar:HasTag("facet-avatar-background-success")).toBe(true)
		presence:set("online")
		expect(ring.Visible).toBe(false)
		expect(find(avatar, "Presence").Visible).toBe(true)
		local sheet = sheetFor(w, themes.neutralPackage())
		expect(rule(sheet, ".facet-avatar-ring::UIStroke"):GetProperties().Transparency).toBe(0)
		expect(rule(sheet, ".facet-avatar-background-success") ~= nil).toBe(true)
		expect(function()
			w.UI.Avatar { name = "A", background = "rainbow" }
		end).toThrow()
		w.stop()
	end)
end)

t.describe("Alert suppression", function()
	t.it("the do-not-ask-again checkbox sits below the actions", function()
		local w = world(function(UI)
			return UI.Alert {
				isPresented = Compose.cell(true),
				title = "Delete save?",
				suppression = { isSuppressed = Compose.cell(false) },
				actions = {
					{ id = "Delete", label = "Delete", role = "destructive" },
					{ id = "Keep", label = "Keep", role = "cancel" },
				},
			}
		end)
		w.step(30)
		local toggle = find(w.screen, "Suppression")
		local actions = find(w.screen, "Actions")
		expect(find(find(w.screen, "AlertContent"), "Suppression")).toBe(nil)
		expect(toggle.Parent).toBe(actions.Parent)
		expect(toggle.LayoutOrder > actions.LayoutOrder).toBe(true)
		w.stop()
	end)
end)

t.describe("Card ring", function()
	t.it("the body's selection image rings the whole card; ringTarget media rings the artwork", function()
		for _, target in { "card", "media" } do
			local w = world(function(UI)
				return UI.Card "C" {
					image = "rbxassetid://1",
					title = "Track",
					onActivate = function() end,
					primaryAction = { label = "Play", onActivate = function() end },
					ringTarget = if target == "media" then "media" else nil,
					Size = UDim2.fromOffset(160, 0),
				}
			end)
			w.step(5)
			local body = find(w.screen, "Body")
			local ring = body.SelectionImageObject
			expect(ring ~= nil and ring.Name == "CardRing").toBe(true)
			expect(ring:HasTag("facet-card-ring")).toBe(true)
			find(w.screen, "C").AbsoluteSize = Vector2.new(160, 200)
			body.AbsoluteSize = Vector2.new(160, 150)
			find(w.screen, "Artwork").AbsoluteSize = Vector2.new(160, 90)
			w.step()
			expect(ring.Size.X.Scale).toBe(1)
			if target == "card" then
				expect(math.abs(ring.Size.Y.Scale - 200 / 150) < 1e-5).toBe(true)
			else
				expect(math.abs(ring.Size.Y.Scale - 90 / 150) < 1e-5).toBe(true)
			end
			w.stop()
		end
		expect(function()
			local w = world(function(UI)
				return UI.Card { image = "rbxassetid://1", title = "T", ringTarget = "shadow" }
			end)
			w.stop()
		end).toThrow()
	end)
end)

t.describe("Slider contained", function()
	t.it("contained paints a knob-thick pill rail and fill", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.Slider "Plain" { value = Compose.cell(0.5) },
				UI.Slider "Contained" { value = Compose.cell(0.5), contained = true },
			}
		end)
		local plain = find(find(w.screen, "Plain"), "Rail")
		local rail = find(find(w.screen, "Contained"), "Rail")
		local fill = find(find(w.screen, "Contained"), "Fill")
		expect(plain.Size.Y.Offset).toBe(6)
		expect(rail.Size.Y.Offset).toBe(24)
		expect(fill.Size.Y.Offset).toBe(24)
		expect(find(rail, "UICorner").CornerRadius.Scale).toBe(1)
		expect(function()
			w.UI.Slider { value = Compose.cell(0.5), contained = "yes" }
		end).toThrow()
		w.stop()
	end)
end)

t.describe("Skeleton corners", function()
	t.it("control and panel read the theme radii", function()
		local package = themes.neutralPackage()
		local w = world(function(UI)
			return UI.VStack {
				UI.Skeleton "Control" { corners = "control" },
				UI.Skeleton "Panel" { corners = "panel" },
			}
		end, { theme = package })
		expect(find(find(w.screen, "Control"), "UICorner").CornerRadius.Offset).toBe(package.metrics.radii.control)
		expect(find(find(w.screen, "Panel"), "UICorner").CornerRadius.Offset).toBe(package.metrics.radii.panel)
		w.stop()
	end)
end)

t.describe("ShortcutHint label", function()
	t.it("the label sits after the keys by default and before them with labelPosition start", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.ShortcutHint "End" { keys = { { "E" } }, label = "Interact" },
				UI.ShortcutHint "Start" { keys = { { "Q" } }, label = "Back", labelPosition = "start" },
			}
		end)
		local function order(root: any): string
			local names = {}
			for _, child in root:GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(names, { child.LayoutOrder, child.Name })
				end
			end
			table.sort(names, function(a, b)
				return a[1] < b[1]
			end)
			local out = {}
			for _, entry in names do
				table.insert(out, entry[2])
			end
			return table.concat(out, ",")
		end
		local ending, starting = find(w.screen, "End"), find(w.screen, "Start")
		expect(order(ending)).toBe("Keys,Label")
		expect(order(starting)).toBe("Label,Keys")
		expect(find(ending, "Label").Text).toBe("Interact")
		expect(find(ending, "Keys").Text).toBe("E")
		w.stop()
	end)
end)

t.describe("filled icon names", function()
	t.it("<name>.fill uses package art, else the regular icon", function()
		local package = themes.neutralPackage()
		local regular = themes.resolveIcon(package, "checkmark")
		expect(regular ~= nil).toBe(true)
		expect(themes.resolveIcon(package, "checkmark.fill")).toBe(regular)
		package.icons = { ["checkmark.fill"] = "rbxassetid://42" }
		expect(themes.resolveIcon(package, "checkmark.fill")).toBe("rbxassetid://42")
		expect(themes.resolveIcon(package, "nothing.fill")).toBe(nil)
	end)
end)
