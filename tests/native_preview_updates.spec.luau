--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engines = require("./lib/native_engine")
local gallery = require("../examples/gallery/client/screen")
local labSettings = require("../examples/facet-lab/src/lab_settings")
local C = Facet.Compose

local function fixture(build)
	local engine = engines.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui, input = engine.new("GuiService"), engine.new("UserInputService")
	input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	input.GetFocusedTextBox = function()
		return nil
	end
	local ctx = {
		Compose = C,
		Facet = Facet,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		guiService = gui,
		viewport = C.cell({ width = 1440, height = 900 }),
	}
	local settings, UI
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		settings = labSettings.new(ctx, input)
		UI = Facet.controls(runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			environment = settings.environment,
			overlayParent = ctx.overlayParent,
			motionLevel = "none",
		})
		return ctx.Host.ScreenGui { ctx.overlayParent, build(UI, ctx.Host, engine.types) }
	end, engine.new("Folder"))
	root.AbsoluteSize = engine.types.Vector2.new(1440, 900)
	ctx.overlayParent.AbsoluteSize = engine.types.Vector2.new(389, 762)
	ctx.overlayParent.AbsolutePosition = engine.types.Vector2.new(400, 50)
	return {
		ctx = ctx,
		settings = settings,
		root = root,
		UI = UI,
		input = input,
		find = function(name)
			return root:FindFirstChild(name, true)
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

t.describe("settings update mounted controls and their presentation bounds", function()
	t.it("automatic lab input follows the device, explicit input wins, and reset restores native facts", function()
		local w = fixture(function(UI)
			return UI.Text { text = "Preview" }
		end)
		local env
		local stop = w.ctx.runtime.mount(function()
			env = w.UI.environment()
			return w.ctx.Host.Folder {}
		end, w.root)
		for _, pair in
			{ { "phone", "Touch" }, { "tablet", "Touch" }, { "tv", "Gamepad" }, { "desktop", "KeyboardAndMouse" } }
		do
			w.settings.set("platform", pair[1])
			t.expect(env.effectiveInput:peek()).toBe(pair[2])
		end
		w.settings.set("input", "pointer")
		w.settings.set("platform", "phone")
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		w.settings.set("input", "automatic")
		t.expect(env.effectiveInput:peek()).toBe("Touch")
		t.expect(w.settings.hover:peek()).toBe(false)
		w.settings.reset()
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		stop()
		w.stop()
	end)

	for _, kind in { "color", "date" } do
		t.it(kind .. " picker adapts in place to touch, console and pointer inside the preview bounds", function()
			local opened = C.cell(false)
			local w = fixture(function(UI, _, T)
				return if kind == "color"
					then UI.ColorPicker "Picker" { value = C.cell(T.Color3.new(1, 0, 0)), isPresented = opened }
					else UI.DateTimePicker "Picker" {
						value = C.cell({ year = 2026, month = 9, day = 30 }),
						onChange = function() end,
						isPresented = opened,
					}
			end)
			w.settings.set("platform", "phone")
			opened:set(true)
			local root = w.find("Picker")
			local panelName = if kind == "color" then "Panel" else "CalendarSurface"
			local panel = w.find(panelName)
			local key = if kind == "color" then "placement" else "route"
			t.expect(root:GetAttribute(key)).toBe("sheet")
			t.expect(panel:IsDescendantOf(w.ctx.overlayParent)).toBe(true)
			if kind == "color" then
				t.expect(panel.Size.X.Offset).toBe(365)
				t.expect(w.find("Readout").LayoutOrder).toBe(2)
			end
			w.settings.set("input", "pointer")
			t.expect(root:GetAttribute(key) ~= "sheet").toBe(true)
			if kind == "color" then
				t.expect(w.find("Readout").LayoutOrder).toBe(5)
			end
			w.settings.set("input", "automatic")
			t.expect(root:GetAttribute(key)).toBe("sheet")
			w.settings.set("platform", "tv")
			t.expect(root:GetAttribute(key)).toBe(if kind == "color" then "center" else "sheet")
			t.expect(w.find(panelName)).toBe(panel)
			t.expect(opened:peek()).toBe(true)
			w.settings.set("platform", "phone")
			local T = w.ctx.types
			local anchor = w.find(if kind == "color" then "Well" else "Field")
			anchor.AbsolutePosition = T.Vector2.new(430, 800)
			anchor.AbsoluteSize = T.Vector2.new(300, 44)
			if kind == "color" then
				w.find("ShowSpectrum").AbsoluteSize = T.Vector2.new(340, 500)
			else
				w.find("Calendar").AbsoluteSize = T.Vector2.new(340, 500)
			end
			w.ctx.overlayParent.AbsoluteSize = T.Vector2.new(844, 390)
			panel.AbsoluteSize = T.Vector2.new(panel.Size.X.Offset, panel.Size.Y.Offset)
			t.expect(panel.Position.Y.Offset >= 0).toBe(true)
			t.expect(panel.Position.Y.Offset + panel.Size.Y.Offset <= 390).toBe(true)
			t.expect(w.find(panelName)).toBe(panel)
			w.stop()
		end)
	end

	t.it("dialog width follows a resized overlay parent rather than the desktop window", function()
		local opened = C.cell(false)
		local w = fixture(function(UI)
			return UI.Dialog {
				isPresented = opened,
				title = "Preview",
				content = function()
					return UI.Text { text = "Keep this inside the preview." }
				end,
				actions = { { id = "close", label = "Close", onActivate = function() end } },
			}
		end)
		opened:set(true)
		local panel = w.find("Panel")
		t.expect(panel:IsDescendantOf(w.ctx.overlayParent)).toBe(true)
		t.expect(panel.Size.X.Offset <= 389).toBe(true)
		w.ctx.overlayParent.AbsoluteSize = w.ctx.types.Vector2.new(300, 500)
		t.expect(panel.Size.X.Offset <= 300).toBe(true)
		t.expect(w.find("Panel")).toBe(panel)
		w.stop()
	end)
end)
return nil
