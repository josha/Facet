--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local nativeApp = require("../bench/native_app")
local overlay = require("./lib/overlay_world")

return function(harness: Verify.Harness)
	harness:case("cooldown sweeps follow the model and keep native activation", {
		id = "native_game_hud::cooldown",
		run = function()
			local remaining = Facet.Compose.cell(6)
			local total = Facet.Compose.cell(12)
			local charges = Facet.Compose.cell(2)
			local count = 0
			local w = overlay.new(function(UI: Facet.Controls)
				return UI.Button "Action" {
					label = "Use",
					icon = "bolt",
					charges = charges,
					cooldown = { remaining = remaining, total = total },
					onActivate = function()
						count += 1
					end,
				}
			end)
			local sweep = w.find("CooldownSweep")
			Verify.expect(sweep.Size.Y.Scale):toBe(0.5)
			Verify.expect(sweep:HasTag("facet-scrim")):toBe(true)
			Verify.expect(sweep.Selectable):toBe(false)
			remaining:set(0)
			w.advance(0.01)
			Verify.expect(sweep.Size.Y.Scale > 0 and sweep.Size.Y.Scale < 0.5):toBe(true)
			w.advance(1)
			Verify.expect(sweep.Visible):toBe(false)
			remaining:set(24)
			w.advance(1)
			Verify.expect(sweep.Size.Y.Scale):toBe(1)
			total:set(48)
			w.advance(1)
			Verify.expect(sweep.Size.Y.Scale):toBe(0.5)
			charges:set(0)
			Verify.expect(w.find("Charges").Text):toBe("0")
			for _, mode in
				{ w.Enum.PreferredInput.KeyboardAndMouse, w.Enum.PreferredInput.Gamepad, w.Enum.PreferredInput.Touch }
			do
				w.engine.environment.poke(w.input, "PreferredInput", mode)
				w.find("Action").Activated:Fire(nil, 1)
			end
			Verify.expect(count):toBe(3)
			w.stop()
		end,
	})
	harness:case("cooldown uses theme duration and reduced motion", {
		id = "native_game_hud::cooldown-motion",
		run = function()
			for _, motion in { "normal", "none" } do
				local remaining = Facet.Compose.cell(10)
				local theme = Facet.themes.neutralPackage()
				theme.metrics.motion.fast = 0.8
				local w = overlay.new(function(UI: Facet.Controls)
					return UI.Button { label = "Action", cooldown = { remaining = remaining, total = 10 } }
				end, { theme = theme, motionLevel = motion })
				remaining:set(0)
				w.advance(0.4)
				local fraction = w.find("CooldownSweep").Size.Y.Scale
				Verify.expect(if motion == "none" then fraction == 0 else math.abs(fraction - 0.5) < 1e-6):toBe(true)
				w.advance(0.4)
				Verify.expect(w.find("CooldownSweep").Size.Y.Scale):toBe(0)
				w.stop()
			end
		end,
	})
	harness:case("cooldown footprint stays near Button and tears down", {
		id = "native_game_hud::footprint",
		run = function()
			local counts: { number } = {}
			for _, decorated in { false, true } do
				local state = nativeApp()
				local stop = state.runtime.mount(function()
					return state.UI.Button {
						label = "Action",
						icon = "bolt",
						cooldown = if decorated then { remaining = state.Compose.cell(6), total = 12 } else nil,
						charges = if decorated then state.Compose.cell(2) else nil,
					}
				end, state.target)
				table.insert(counts, #state.target:GetDescendants())
				stop()
				state.dispose()
				Verify.expect(state.engine.census().connections):toBe(0)
			end
			Verify.expect(counts[2] - counts[1]):toBe(4)
		end,
	})
	harness:case("rich help shares hover focus and long press placement", {
		id = "native_game_hud::rich-help",
		run = function()
			for _, mode in { "hover", "focus", "touch" } do
				local cost = Facet.Compose.cell("Cost: 12")
				local help: Facet.HelpSpec = {
					title = "Action details",
					body = "A short description.",
					rows = { { label = "Range", value = "Near" } },
					cost = cost,
					cooldown = "Cooldown: 8 seconds",
					flavour = "A quiet detail.",
				}
				local w = overlay.new(function(UI: Facet.Controls)
					return UI.Button "Action" { label = "Action", help = help }
				end, { motionLevel = "none" })
				local anchor = w.find("Action")
				w.engine.environment.poke(anchor, "AbsolutePosition", w.Vector2.new(300, 200))
				w.engine.environment.poke(anchor, "AbsoluteSize", w.Vector2.new(64, 64))
				if mode == "touch" then
					w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
					anchor.TouchLongPress:Fire({ w.Vector2.new(320, 220) }, w.Enum.UserInputState.Begin)
				elseif mode == "focus" then
					w.gui.SelectedObject = anchor
				else
					w.engine.environment.poke(anchor, "GuiState", w.Enum.GuiState.Hover)
				end
				w.advance(0.5)
				Verify.expect(w.find("HelpRow1").Text):toBe("Range: Near")
				Verify.expect(w.find("HelpFlavour").Text):toBe("A quiet detail.")
				cost:set("Cost: 9")
				Verify.expect(w.find("HelpCost").Text):toBe("Cost: 9")
				Verify.expect(w.find("HelpCooldown").Text):toBe("Cooldown: 8 seconds")
				w.engine.environment.poke(w.find("Help"), "AbsoluteSize", w.Vector2.new(240, 180))
				w.advance(1 / 60, 2)
				Verify.expect(w.find("Help"):HasTag("facet-tooltip")):toBe(true)
				w.engine.environment.poke(w.screen, "AbsoluteSize", w.Vector2.new(360, 640))
				local panel = w.find("Help")
				local x = panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X
				local y = panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
				Verify.expect(x >= 8 and x + 240 <= 352):toBe(true)
				Verify.expect(y >= 8 and y + 180 <= 632):toBe(true)
				w.stop()
			end
		end,
	})
	harness:case("world portals share the sheet provider and lifetime for both surfaces", {
		id = "native_game_hud::world-surfaces",
		run = function()
			local state = nativeApp()
			local Host = state.Host
			local sheet: StyleSheet
			local source: StyleLink
			local billboard: BillboardGui
			local surface: SurfaceGui
			local stop = state.runtime.mount(function()
				sheet = Host.StyleSheet {}
				source = Host.StyleLink { StyleSheet = state.Compose.static(sheet) }
				billboard = Host.BillboardGui "Nameplate" {}
				surface = Host.SurfaceGui "Prompt" {}
				return Host.Folder {
					billboard,
					surface,
					Host.ScreenGui {
						sheet,
						source,
						state.UI.provide(function()
							return state.UI.worldSurface(billboard, function()
								Verify.expect(Facet.controls(state.runtime)):toBe(state.UI)
								return state.UI.Text { text = "Nameplate" }
							end)
						end),
						state.UI.worldSurface(surface, function()
							return state.UI.Button { label = "Interact" }
						end),
					},
				}
			end, state.target)
			for _, layer in { billboard, surface } do
				local inherited = layer:FindFirstChildWhichIsA("StyleLink")
				assert(inherited and inherited:IsA("StyleLink"))
				Verify.expect(inherited.StyleSheet):toBe(sheet)
			end
			local replacement: StyleSheet = state.engine.new("StyleSheet")
			source.StyleSheet = replacement
			local inherited = billboard:FindFirstChildWhichIsA("StyleLink")
			assert(inherited and inherited:IsA("StyleLink"))
			Verify.expect(inherited.StyleSheet):toBe(replacement)
			stop()
			replacement:Destroy()
			state.dispose()
			Verify.expect(state.engine.census().connections):toBe(0)
		end,
	})
	harness:case("world surface performance scene updates 64 portals without rebuilding layers", {
		id = "native_game_hud::world-perf",
		run = function()
			local state = nativeApp()
			local build = require("../examples/performance/world_surfaces")
			local step: () -> ()
			local stop = state.runtime.mount(function()
				local part = state.Host.Part { Anchored = true }
				local scene, update = build({
					runtime = state.runtime,
					UI = state.UI,
					Host = Facet.host(state.runtime),
					parent = state.target,
					adornee = part,
					size = state.types.UDim2.fromOffset(160, 40),
					count = 64,
				})
				step = update
				return state.Host.Folder { part, scene }
			end, state.target)
			local count = #state.target:GetDescendants()
			for _ = 1, 10 do
				step()
			end
			Verify.expect(#state.target:GetDescendants()):toBe(count)
			local layers = 0
			for _, node in state.target:GetChildren() do
				if node:IsA("BillboardGui") then
					layers += 1
					local text = node:FindFirstChildWhichIsA("TextLabel")
					assert(text and text:IsA("TextLabel"))
					Verify.expect(string.find(text.Text, ": 10", 1, true) ~= nil):toBe(true)
				end
			end
			Verify.expect(layers):toBe(64)
			stop()
			Verify.expect(#state.target:GetChildren()):toBe(0)
			state.dispose()
			Verify.expect(state.engine.census().connections):toBe(0)
		end,
	})
end
