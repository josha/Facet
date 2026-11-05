--!strict

local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Lute = require("../tools/vendor/verify/src/lute")

return function(harness: Verify.Harness)
	local Facet = require("../src")
	local Editor = require("../src/vendor/compose/design-editor")
	local engines = require("./lib/native_engine")

	local function workspace(test: Verify.Context)
		local engine = engines.new()
		local globals = (table.clone(engine.types) :: unknown) :: { [string]: unknown }
		local services: { [string]: unknown } = {}
		local function service(name: string): unknown
			if name == "CollectionService" then
				return nil
			end
			if not services[name] then
				services[name] = engine.new(name)
			end
			return services[name]
		end
		globals.game = {
			GetService = function(_self: unknown, name: string): unknown
				return service(name)
			end,
		}
		local loader = Lute.loader.new({ globals = globals })
		local loaded = loader.require("src") :: Facet.Facet
		local runtime = loaded.Roblox.createRuntime(engine)
		local dispose = runtime.dispose
		local disposed = 0
		runtime.dispose = function(self)
			disposed += 1
			dispose(self)
		end
		test:defer(function()
			runtime:dispose()
		end)
		local roblox = table.clone(loaded.Roblox)
		local created = 0
		roblox.createRuntime = function()
			created += 1
			return runtime
		end
		roblox.designEnvironment = function()
			local types = engine.types
			return loaded.Roblox.designEnvironment({
				service = service,
				values = {
					vector2 = types.Vector2.new,
					vector3 = types.Vector3.new,
					udim = types.UDim.new,
					udim2 = types.UDim2.new,
					color = types.Color3.new,
					font = function(family: string, weight: string): unknown
						return types.Font.new(family, types.Enum.FontWeight:FromName(weight))
					end,
					enum = function(name: string, item: string): unknown
						return types.Enum[name][item]
					end,
					cframe = function(): unknown
						return types.CFrame.new()
					end,
					raycastParams = function(): unknown
						return nil
					end,
				},
			})
		end
		local surface = loaded.bind(loaded.Compose, roblox)
		local registry: { [string]: Facet.DesignRegistered } = {}
		local samples: { Facet.DesignStudioSample } = {}
		local environments: { Facet.Environment } = {}
		for _, name in { "Emblem", "Bulletin" } do
			local inputs: { Facet.DesignInput } = {
				{ id = "label", kind = "value", type = "string", required = true, preview = "Ready" },
			}
			registry[name] = {
				contract = {
					inputs = inputs,
					outputs = {},
				},
				call = "Components." .. name,
				prelude = { "local Components = require(game.ReplicatedStorage.Components)" },
				build = function(controls: unknown, props: { [string]: unknown }, nodeName: string): unknown
					local UI = controls :: Facet.Controls
					local label = props.label
					assert(type(label) == "string")
					table.insert(environments, UI.environment())
					return UI.Text(nodeName) { text = label }
				end,
			}
			for _, state in { "Ready", "Busy", "Empty", "Failed" } do
				table.insert(samples, { design = name, name = state, props = { label = name .. " " .. state } })
			end
		end
		local parent = engine.new("ScreenGui")
		test:defer(function()
			parent:Destroy()
		end)
		return {
			surface = surface,
			engine = engine,
			runtime = runtime,
			parent = parent,
			environments = environments,
			options = { registry = registry, samples = samples },
			created = function(): number
				return created
			end,
			disposed = function(): number
				return disposed
			end,
		}
	end

	local function button(editor: Facet.DesignStudioEditor, name: string): VerifyRoblox.Instance
		local root = VerifyRoblox.assertInstance(editor.root)
		local found = root:FindFirstChild(name, true)
		assert(found and found:IsA("TextButton"), "Missing visible control: " .. name)
		Verify.expect(found.Visible):toBe(true)
		return found
	end

	local function label(editor: Facet.DesignStudioEditor): string
		local stage = assert(editor.canvas.current().stage)
		local text = VerifyRoblox.assertInstance(assert(stage.nodes.n1))
		local value = text.Text
		assert(type(value) == "string")
		return value
	end

	harness:suite("host Compose Design workspace", function()
		harness:case("opens two registered Designs and eight sample states through editor commands and controls", {
			id = "compose_design_host::registry samples and previews",
			run = function(test: Verify.Context)
				local host = workspace(test)
				local captured: { string } = {}
				local options: Facet.DesignStudioOptions = {
					registry = host.options.registry,
					samples = host.options.samples,
					capture = function(name: string, frame: Facet.DesignStudioFrame): { string }
						table.insert(captured, name .. "/" .. frame.device.id)
						return { "captures/" .. name .. ".png" }
					end,
				}
				local kit = host.surface.composeDesign(options)
				Verify.expect(host.created()):toBe(0)
				local editor = kit.edit(host.parent, "Emblem")
				test:defer(editor.dispose)
				Verify.expect(host.created()):toBe(1)
				Verify.expect(#host.parent:GetChildren()):toBe(1)
				local read = editor.execute({ action = "Read" })
				Verify.expect(read.ok):toBe(true)
				Verify.expect(read.design):toBe("Emblem")
				Verify.expect(read.previews.Sample):toBe("Emblem/Ready")
				Verify.expect(#read.previewChoices.Sample):toBe(8)
				for _, sample in options.samples do
					local choice = sample.design .. "/" .. sample.name
					local result = editor.execute({ action = "Preview", name = "Sample", choice = choice })
					Verify.expect(result.ok):toBe(true)
					Verify.expect(result.design):toBe(sample.design)
					Verify.expect(result.previews.Sample):toBe(choice)
					Verify.expect(label(editor)):toBe(sample.props.label)
				end
				for _, choice in read.previewChoices.Sample do
					host.engine.environment.fire(button(editor, "Sample"), "Activated")
					local result = editor.execute({ action = "Read" })
					Verify.expect(result.previews.Sample):toBe(choice)
					Verify.expect(button(editor, "Sample").Text):toBe(choice)
					Verify.expect(label(editor)):toBe(string.gsub(choice, "/", " "))
				end
				for _, id in read.devices do
					local result = editor.execute({ action = "Device", id = id })
					Verify.expect(result.ok):toBe(true)
					Verify.expect(result.device):toBe(id)
					Verify.expect(editor.canvas.current().device.id):toBe(id)
					Verify.expect(label(editor)):toBe("Bulletin Failed")
				end
				for _, id in read.devices do
					host.engine.environment.fire(button(editor, "Device"), "Activated")
					Verify.expect(editor.execute({ action = "Read" }).device):toBe(id)
					Verify.expect(button(editor, "Device").Text):toBe(editor.canvas.current().device.name)
				end
				for _, name in { "Theme", "Text size" } do
					local choices = read.previewChoices[name]
					for _, choice in choices do
						local result = editor.execute({ action = "Preview", name = name, choice = choice })
						Verify.expect(result.ok):toBe(true)
						Verify.expect(result.previews[name]):toBe(choice)
						Verify.expect(button(editor, name).Text):toBe(choice)
						if name == "Text size" then
							Verify.expect(host.environments[#host.environments].preferredTextSize:peek()):toBe(choice)
						else
							for _, frame in editor.canvas.frames() do
								local sheet = VerifyRoblox.assertInstance(frame.root)
									:FindFirstChildWhichIsA("StyleSheet", true)
								assert(sheet)
								for _, palette in host.surface.themes.neutralPackage().style.themes do
									if palette.name == choice then
										local color = palette.colors.content
										Verify.expect(sheet:GetAttribute("FacetColor_content"))
											:toBe(host.engine.types.Color3.new(color.r, color.g, color.b))
									end
								end
							end
						end
					end
					for _, choice in choices do
						host.engine.environment.fire(button(editor, name), "Activated")
						Verify.expect(editor.execute({ action = "Read" }).previews[name]):toBe(choice)
						Verify.expect(button(editor, name).Text):toBe(choice)
					end
				end
				local capture = editor.execute({ action = "Capture", name = "HostSample" })
				Verify.expect(capture.ok):toBe(true)
				Verify.expect(capture.files[1]):toBe("captures/HostSample.png")
				Verify.expect(captured[1]):toBe("HostSample/" .. editor.canvas.current().device.id)
				host.engine.environment.fire(button(editor, "Capture"), "Activated")
				Verify.expect(#captured):toBe(2)
				local invalid = editor.execute({ action = "Preview", name = "Sample", choice = "Missing" })
				Verify.expect(invalid.ok):toBe(false)
				Verify.expect(invalid.previews.Sample):toBe("Bulletin/Failed")
				Verify.expect(editor.execute({ action = "Close" }).closed):toBe(true)
				Verify.expect(#host.parent:GetChildren()):toBe(0)
				Verify.expect(editor.execute({ action = "Read" }).closed):toBe(true)
				Verify.expect(editor.execute({ action = "Close" }).ok):toBe(true)
				Verify.expect(editor.execute({ action = "Device", id = read.devices[1] }).ok):toBe(false)
				Verify.expect(host.created()):toBe(1)
				Verify.expect(host.disposed()):toBe(1)
			end,
		})

		harness:case("uses configured stages and previews and closes from its visible control", {
			id = "compose_design_host::configured previews and visible close",
			run = function(test: Verify.Context)
				local host = workspace(test)
				local options: Facet.DesignStudioOptions = {
					registry = host.options.registry,
					samples = host.options.samples,
					stages = { Editor.devices.get("monitor"), Editor.devices.get("phone-portrait") },
					themes = { "Dark", "Light" },
					textSizes = { "Largest", "Medium" },
				}
				local editor = host.surface.composeDesign(options).edit(host.parent, "Bulletin")
				test:defer(editor.dispose)
				local read = editor.execute({ action = "Read" })
				Verify.expect(read.design):toBe("Bulletin")
				Verify.expect(read.device):toBe("monitor")
				Verify.expect(#read.devices):toBe(2)
				Verify.expect(read.previews.Theme):toBe("Dark")
				Verify.expect(read.previews["Text size"]):toBe("Largest")
				Verify.expect(#read.previewChoices["Text size"]):toBe(2)
				Verify.expect(label(editor)):toBe("Bulletin Ready")
				host.engine.environment.fire(button(editor, "Device"), "Activated")
				Verify.expect(editor.execute({ action = "Read" }).device):toBe("phone-portrait")
				host.engine.environment.fire(button(editor, "Theme"), "Activated")
				host.engine.environment.fire(button(editor, "Text size"), "Activated")
				Verify.expect(editor.execute({ action = "Read" }).previews.Theme):toBe("Light")
				Verify.expect(editor.execute({ action = "Read" }).previews["Text size"]):toBe("Medium")
				host.engine.environment.fire(button(editor, "Close"), "Activated")
				Verify.expect(editor.execute({ action = "Read" }).closed):toBe(true)
				Verify.expect(#host.parent:GetChildren()):toBe(0)
				Verify.expect(host.disposed()):toBe(1)
			end,
		})

		harness:case("retains the base Facet workspace and exposes its editor", {
			id = "compose_design_host::base workspace editor",
			run = function(test: Verify.Context)
				local host = workspace(test)
				local editor = host.surface.composeDesign().edit(host.parent, "Panel")
				test:defer(editor.dispose)
				Verify.expect(editor.execute({ action = "Read" }).design):toBe("Panel")
				Verify.expect(editor.session.library.name):toBe("Facet")
				Verify.expect(editor.session.document:peek().root.kind):toBe("Screen")
				Verify.expect(editor.execute({ action = "Capture", name = "Panel" }).ok):toBe(false)
				editor.dispose()
				Verify.expect(#host.parent:GetChildren()):toBe(0)
				Verify.expect(host.disposed()):toBe(1)
			end,
		})

		harness:case("rejects invalid host configuration and releases failed workspaces", {
			id = "compose_design_host::invalid configuration cleanup",
			run = function(test: Verify.Context)
				local host = workspace(test)
				local unknown: Facet.DesignStudioOptions = {
					registry = host.options.registry,
					samples = { { design = "Missing", name = "Ready", props = {} } },
				}
				Verify.expect(pcall(host.surface.composeDesign, unknown)):toBe(false)
				local duplicate: Facet.DesignStudioOptions = {
					registry = host.options.registry,
					samples = { host.options.samples[1], host.options.samples[1] },
				}
				Verify.expect(pcall(host.surface.composeDesign, duplicate)):toBe(false)
				local options: Facet.DesignStudioOptions = {
					registry = host.options.registry,
					samples = host.options.samples,
				}
				options.stages = {}
				Verify.expect(pcall(host.surface.composeDesign, options)):toBe(false)
				options.stages = nil
				options.themes = { "Missing" }
				Verify.expect(pcall(host.surface.composeDesign, options)):toBe(false)
				options.themes = nil
				options.textSizes = { "Missing" }
				Verify.expect(pcall(host.surface.composeDesign, options)):toBe(false)
				options.textSizes = nil
				local kit = host.surface.composeDesign(options)
				Verify.expect(pcall(kit.edit, host.parent, "Missing")):toBe(false)
				Verify.expect(host.created()):toBe(0)
				options.samples[1].props.label = 42
				Verify.expect(pcall(kit.edit, host.parent, "Emblem")):toBe(false)
				Verify.expect(host.created()):toBe(1)
				Verify.expect(host.disposed()):toBe(1)
				Verify.expect(#host.parent:GetChildren()):toBe(0)
				local collision = workspace(test)
				local conflict: Facet.DesignStudioOptions = {
					registry = { Text = collision.options.registry.Emblem },
					samples = { { design = "Text", name = "Ready", props = { label = "Ready" } } },
				}
				local conflicting = collision.surface.composeDesign(conflict)
				Verify.expect(pcall(conflicting.edit, collision.parent, "Text")):toBe(false)
				Verify.expect(collision.created()):toBe(1)
				Verify.expect(collision.disposed()):toBe(1)
				Verify.expect(#collision.parent:GetChildren()):toBe(0)
			end,
		})
	end)
end
