--!strict
local Verify = require("../tools/vendor/verify/src/core")
local LayoutProps = require("../src/ui/layout_props")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function make(options: { [string]: any }?): (any, any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = (engine.new("GuiService") :: unknown) :: GuiService
		local T = engine.types
		engine.environment.fakeOn(gui, "GetGuiInset", function()
			return T.Vector2.new(0, 58), T.Vector2.zero
		end)
		engine.environment.fakeOn(gui, "GetInsetArea", function()
			return T.Rect.new(0, 0, 1280, 720)
		end)
		engine.environment.poke(gui, "TopbarInset", T.Rect.new(0, 0, 0, 0))
		local config: { [string]: any } = { types = T, guiService = gui, services = { GuiService = gui } }
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		return engine, runtime, Facet.controls(runtime, config :: any), gui
	end

	local function sized(engine: any, node: any, width: number, height: number)
		engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(width, height))
	end

	local function form(Host: any, name: string): any
		return Host.Frame { Name = name }
	end

	local NAMES = { "Rounds", "Tasks", "Health", "Clock", "Strip", "Rail", "Readout", "Actions" }

	local function hud(UI: any, Host: any, forms: any, topbar: any?)
		local function region(name: string, spec: { [any]: any }): any
			spec.form = forms[name]
			spec.Name = name
			return UI.Region(spec)
		end
		return UI.Composition "Hud" {
			gap = 8,
			padding = 0,
			topbar = topbar,
			region("Rounds", { zone = "topLeft", rank = 1, form(Host, "RoundsFull") }) :: unknown,
			region("Tasks", {
				zone = "left",
				rank = 7,
				mayDrop = true,
				form(Host, "TasksFull"),
				form(Host, "TasksChip"),
			}),
			region("Health", { zone = "bottomLeft", rank = 5, form(Host, "HealthFull"), form(Host, "HealthChip") }),
			region("Clock", { zone = "top", rank = 2, form(Host, "ClockFull"), form(Host, "ClockChip") }),
			region("Strip", { zone = "topbar", rank = 6, form(Host, "Objective") }),
			region("Rail", { zone = "topRight", rank = 4, form(Host, "RailFull"), form(Host, "RailChip") }),
			region("Readout", { zone = "topRight", rank = 9, mayDrop = true, form(Host, "ReadoutText") }),
			region("Actions", { zone = "bottomRight", rank = 3, form(Host, "ActionsFull") }),
		}
	end

	local SIZES: { [string]: { number } } = {
		RoundsFull = { 120, 44 },
		TasksFull = { 240, 130 },
		TasksChip = { 90, 44 },
		HealthFull = { 150, 40 },
		HealthChip = { 60, 44 },
		ClockFull = { 170, 60 },
		ClockChip = { 80, 44 },
		Objective = { 130, 32 },
		RailFull = { 130, 132 },
		RailChip = { 80, 44 },
		ReadoutText = { 110, 16 },
		ActionsFull = { 44, 148 },
	}

	local function mount(options: { [string]: any }?, topbar: any?): (any, any, any, any, () -> ())
		local engine, runtime, UI, gui = make(options)
		local cells = {}
		for _, name in NAMES do
			cells[name] = Compose.cell(1)
		end
		local forms = {
			cells = cells,
			peek = function()
				local chosen = {}
				for name, cell in cells do
					chosen[name] = cell:peek()
				end
				return chosen
			end,
		}
		local layer = engine.new("ScreenGui")
		layer.Parent = engine.new("Folder")
		local root: any
		runtime.mount(function()
			root = hud(UI, runtime.constructors, cells, topbar)
			return root
		end, layer)
		for name, size in SIZES do
			sized(engine, root:FindFirstChild(name, true), size[1], size[2])
		end
		for _, node in root:GetDescendants() do
			if node.Name == "Reveal" then
				sized(engine, node, 28, 20)
			end
		end
		return root, engine, forms, gui, function()
			runtime:dispose()
		end
	end

	type RowOptions = {
		captions: boolean,
		padding: { bottom: string }?,
		mayDrop: boolean?,
		reveal: boolean?,
		form: typeof(require("@repo/tools/typecheck/aliases").NumberCell)?,
		shown: typeof(require("@repo/tools/typecheck/aliases").BooleanCell)?,
	}

	local function actionRow(options: RowOptions)
		local engine, runtime, UI = make()
		local layer = engine.new("ScreenGui")
		layer.Parent = engine.new("Folder")
		local root: Frame
		runtime.mount(function()
			local function circle(name: string)
				return UI.Button(name) {
					name = name,
					icon = "view.grid",
					shape = "circle",
					caption = if options.captions then name else nil,
					controlSize = "regular",
				}
			end
			root = UI.Composition "Hud" {
				gap = 8,
				padding = 0,
				topbar = false,
				UI.Region "Actions" {
					zone = "bottomLeft",
					rank = 2,
					mayDrop = options.mayDrop,
					reveal = options.reveal,
					form = options.form,
					Visible = options.shown,
					UI.HStack "Circles" {
						gap = 12,
						padding = options.padding,
						circle("Shop"),
						circle("Garage"),
						circle("Pass"),
					},
				},
				UI.Region "Go" { zone = "bottomRight", rank = 1, UI.Button "Race" { label = "Race" } },
			}
			return root
		end, layer)
		local V2 = engine.types.Vector2
		local tall = if options.padding then 64 else 44
		local row = root:FindFirstChild("Circles", true)
		engine.environment.poke(row, "AbsolutePosition", V2.new(0, 700 - tall))
		sized(engine, row, 156, tall)
		sized(engine, root:FindFirstChild("Race", true), 80, 44)
		for index, name in { "Shop", "Garage", "Pass" } do
			local caption = (root:FindFirstChild(name, true) :: TextButton):FindFirstChild("Caption")
			if caption then
				engine.environment.poke(caption, "AbsolutePosition", V2.new(56 * index - 54, 748 - tall))
				sized(engine, caption, 40, 14)
			end
		end
		sized(engine, root:FindFirstChild("Zones"), 390, 700)
		return root, engine, function()
			runtime:dispose()
		end
	end

	verifyHarness:suite("Composition", function()
		verifyHarness:case("names the regions that would not fit a phone on a larger screen", {
			id = "native_composition::Composition::names the regions that would not fit a phone on a larger screen",
			run = function()
				local root, engine, stop = actionRow({ captions = false })
				sized(engine, root:FindFirstChild("Zones"), 1920, 1080)
				Verify.expect(root:GetAttribute("FacetUnfit")):toBeNil()
				sized(engine, root:FindFirstChild("Circles", true), 330, 44)
				sized(engine, root:FindFirstChild("Race", true), 200, 44)
				local unfit = tostring(root:GetAttribute("FacetUnfit"))
				Verify.expect(root:GetAttribute("FacetUnfit") ~= nil):toBe(true)
				Verify.expect(string.find(unfit, "358 by 812: Actions, Go", 1, true) ~= nil):toBe(true)
				Verify.expect((string.find(unfit, "812 by 358", 1, true))):toBeNil()
				sized(engine, root:FindFirstChild("Circles", true), 156, 44)
				sized(engine, root:FindFirstChild("Race", true), 80, 44)
				Verify.expect(root:GetAttribute("FacetUnfit")):toBeNil()
				stop()
			end,
		})

		verifyHarness:case("keeps every zone inside the TV safe area when it is the screen root", {
			id = "native_composition::Composition::keeps every zone inside the TV safe area when it is the screen root",
			run = function()
				local root, engine, _, _, stop = mount({ environment = { viewingDistance = "ten-foot" } })
				local T = engine.types
				local inset = root:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(math.abs(inset.PaddingLeft.Scale - 90 / 1920) < 1e-6):toBe(true)
				Verify.expect(math.abs(inset.PaddingRight.Scale - 90 / 1920) < 1e-6):toBe(true)
				Verify.expect(math.abs(inset.PaddingBottom.Scale - 60 / 1080) < 1e-6):toBe(true)
				Verify.expect(math.abs(inset.PaddingTop.Scale - 60 / 1080) < 1e-6):toBe(true)
				local holder = engine.new("Frame")
				holder.Parent = root.Parent
				root.Parent = holder
				Verify.expect(inset.PaddingLeft):toBe(T.UDim.new(0, inset.PaddingLeft.Offset))
				stop()
				local near, _, _, _, stopNear = mount()
				Verify.expect(near:FindFirstChildWhichIsA("UIPadding").PaddingLeft.Scale):toBe(0)
				stopNear()
			end,
		})
		verifyHarness:case(
			"rides the free strip of the top bar in a TopbarSafeInsets ScreenGui, or leads the top zone",
			{
				id = "native_composition::Composition::rides the free strip of the top bar in a TopbarSafeInsets ScreenGui, or leads the top zone",
				run = function()
					local ride = Compose.cell(true)
					local root: any, engine, forms, gui, stop = mount(nil, ride)
					local T = engine.types
					local region = root:FindFirstChild("Strip", true)
					Verify.expect(region.Parent.Name):toBe("Landed")
					Verify.expect(region.Parent.Parent.Name):toBe("Top")
					Verify.expect(region.Parent.LayoutOrder):toBe(0)
					engine.environment.poke(gui, "TopbarInset", T.Rect.new(164, 0, 844, 58))
					Verify.expect(region.Parent.Name):toBe("Middle")
					local strip = region:FindFirstAncestorWhichIsA("ScreenGui")
					Verify.expect(strip.Name):toBe("CompositionTopbar")
					Verify.expect(strip.ScreenInsets):toBe(T.Enum.ScreenInsets.TopbarSafeInsets)
					Verify.expect(root:GetAttribute("FacetGameplayGuard")):toBe(false)
					Verify.expect(strip:GetAttribute("FacetGameplayGuard")):toBe(false)
					Verify.expect(strip.Parent):toBe(root:FindFirstAncestorWhichIsA("ScreenGui").Parent)
					Verify.expect(strip:FindFirstChild("Topbar").Size):toBe(T.UDim2.fromScale(1, 1))
					local row = strip:FindFirstChild("Topbar"):FindFirstChildWhichIsA("UIPadding")
					Verify.expect(row.PaddingTop):toBe(T.UDim.new(0, 12))
					Verify.expect(row.PaddingBottom):toBe(T.UDim.new(0, 2))
					Verify.expect(row.PaddingLeft):toBe(T.UDim.new(0, 8))
					Verify.expect(row.PaddingRight):toBe(T.UDim.new(0, 8))
					sized(engine, strip, 680, 58)
					sized(engine, root:FindFirstChild("Zones"), 844, 330)
					Verify.expect(forms.peek().Strip):toBe(1)
					sized(engine, strip, 0, 0)
					Verify.expect(region.Parent.Name):toBe("Middle")
					Verify.expect(forms.peek().Strip):toBe(1)
					sized(engine, strip, 680, 58)
					ride:set(false)
					Verify.expect(region.Parent.Name):toBe("Landed")
					Verify.expect(strip.Parent):toBe(nil)
					stop()
					Verify.expect(strip.Parent):toBe(nil)
				end,
			}
		)

		verifyHarness:case(
			"lands its top bar regions in the top zone when the strip cannot hold their smallest forms",
			{
				id = "native_composition::Composition::lands its top bar regions in the top zone when the strip cannot hold their smallest forms",
				run = function()
					local root, engine, forms, gui, stop = mount(nil, true)
					local T = engine.types
					local region = root:FindFirstChild("Strip", true)
					engine.environment.poke(gui, "TopbarInset", T.Rect.new(250, 0, 350, 58))
					local strip = region:FindFirstAncestorWhichIsA("ScreenGui")
					Verify.expect(strip.Name):toBe("CompositionTopbar")
					sized(engine, strip, 100, 58)
					sized(engine, root:FindFirstChild("Zones"), 844, 330)
					Verify.expect(region.Parent.Name):toBe("Landed")
					Verify.expect(region.Parent.Parent.Name):toBe("Top")
					Verify.expect(strip.Parent):toBe(root:FindFirstAncestorWhichIsA("ScreenGui").Parent)
					Verify.expect(forms.peek().Strip):toBe(1)
					sized(engine, strip, 680, 58)
					Verify.expect(region.Parent.Name):toBe("Middle")
					stop()
				end,
			}
		)

		verifyHarness:case("keeps a leading top bar region beside the engine buttons while a later region lands", {
			id = "native_composition::Composition::keeps a leading top bar region beside the engine buttons while a later region lands",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local gear: Declared =
					{ zone = "topbar" :: "topbar", rank = 1, mayDrop = false, sizes = { { x = 44, y = 44 } } }
				local info: Declared = {
					zone = "topbar" :: "topbar",
					rank = 1,
					mayDrop = false,
					sizes = { { x = 240, y = 33 }, { x = 187, y = 24 } },
				}
				local forms, landed = resolver.resolve(327, 628, 8, { gear, info }, { x = 195, y = 58 })
				Verify.expect(landed[1]):toBe(false)
				Verify.expect(landed[2]):toBe(true)
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(1)
				forms, landed = resolver.resolve(673, 290, 8, { gear, info }, { x = 541, y = 58 })
				Verify.expect(landed[2]):toBe(false)
				Verify.expect(forms[2]):toBe(1)

				local engine, runtime, UI, gui = make()
				local T = engine.types
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local lead, middle, trail
				runtime.mount(function()
					local Host = runtime.constructors
					lead = UI.Region {
						Name = "Gear",
						zone = "topbar",
						rank = 1,
						leading = true,
						Host.Frame { Name = "GearFull" },
					}
					middle = UI.Region { Name = "Info", zone = "topbar", rank = 1, Host.Frame { Name = "InfoFull" } }
					trail = UI.Region {
						Name = "Menu",
						zone = "topbar",
						rank = 1,
						trailing = true,
						Host.Frame { Name = "MenuFull" },
					}
					return UI.Composition { gap = 8, padding = 0, lead, middle, trail }
				end, layer)
				engine.environment.poke(gui, "TopbarInset", T.Rect.new(164, 0, 844, 58))
				Verify.expect(lead.Parent.Name):toBe("Leading")
				Verify.expect(middle.Parent.Name):toBe("Middle")
				Verify.expect(trail.Parent.Name):toBe("Trailing")
				Verify.expect(lead.Parent.Parent):toBe(middle.Parent.Parent)
				Verify.expect(trail.Parent.Parent):toBe(middle.Parent.Parent)
				Verify.expect(trail.Parent.LayoutOrder > middle.Parent.LayoutOrder):toBe(true)
				engine.environment.poke(gui, "TopbarInset", T.Rect.new(0, 0, 0, 0))
				Verify.expect(middle.Parent.Name):toBe("Landed")
				Verify.expect(middle.Parent.Parent.Name):toBe("Top")
				Verify.expect(trail.Parent.Name):toBe("LandedTrailing")
				Verify.expect(trail.Parent.Parent.Name):toBe("TopRight")
				Verify.expect(trail.Parent.LayoutOrder):toBe(0)
				Verify.expect(lead.Parent.Name):toBe("LandedLeading")
				Verify.expect(lead.Parent.Parent.Name):toBe("TopLeft")
				runtime:dispose()
			end,
		})

		verifyHarness:case("counts the gap beside an empty strip lane when it fits top bar regions", {
			id = "native_composition::Composition::counts the gap beside an empty strip lane when it fits top bar regions",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local wallet: Declared = {
					zone = "topbar" :: "topbar",
					rank = 2,
					mayDrop = false,
					leading = true,
					sizes = { { x = 44, y = 44 } },
				}
				local menu: Declared = {
					zone = "topbar" :: "topbar",
					rank = 1,
					mayDrop = false,
					trailing = true,
					sizes = { { x = 44, y = 44 } },
				}
				local _, landed = resolver.resolve(673, 290, 8, { wallet, menu }, { x = 100, y = 44 })
				Verify.expect(landed[1]):toBe(false)
				Verify.expect(landed[2]):toBe(false)
				_, landed = resolver.resolve(673, 290, 8, { wallet, menu }, { x = 100, y = 44, lanes = 3 })
				Verify.expect(landed[1]):toBe(true)
				Verify.expect(landed[2]):toBe(false)
				_, landed = resolver.resolve(673, 290, 8, { wallet, menu }, { x = 104, y = 44, lanes = 3 })
				Verify.expect(landed[1]):toBe(false)
				Verify.expect(landed[2]):toBe(false)
			end,
		})

		verifyHarness:case("ends the top bar strip at the composition's own edge padding", {
			id = "native_composition::Composition::ends the top bar strip at the composition's own edge padding",
			run = function()
				local cases: { { padding: unknown, right: number } } = {
					{ padding = 16, right = 16 },
					{ padding = 0, right = 8 },
					{ padding = { top = 4, right = 24 }, right = 24 },
					{ padding = { left = 30 }, right = 8 },
				}
				for _, case in cases do
					local engine, runtime, UI, gui = make()
					local T = engine.types
					local layer = engine.new("ScreenGui")
					layer.Parent = engine.new("Folder")
					local menu
					runtime.mount(function()
						local Host = runtime.constructors
						menu = UI.Region {
							Name = "Menu",
							zone = "topbar",
							rank = 1,
							trailing = true,
							Host.Frame { Name = "MenuFull" },
						}
						return UI.Composition { gap = 8, padding = case.padding, menu }
					end, layer)
					engine.environment.poke(gui, "TopbarInset", T.Rect.new(164, 0, 844, 58))
					local strip = menu:FindFirstAncestorWhichIsA("ScreenGui")
					Verify.expect(strip.Name):toBe("CompositionTopbar")
					local row = strip:FindFirstChild("Topbar"):FindFirstChildWhichIsA("UIPadding")
					Verify.expect(row.PaddingLeft):toBe(T.UDim.new(0, 8))
					Verify.expect(row.PaddingRight):toBe(T.UDim.new(0, case.right))
					sized(engine, menu:FindFirstChild("MenuFull", true), 40, 40)
					sized(engine, layer:FindFirstChild("Zones", true), 844, 330)
					sized(engine, strip, 56 + case.right, 58)
					Verify.expect(menu.Parent.Name):toBe("Trailing")
					sized(engine, strip, 55 + case.right, 58)
					Verify.expect(menu.Parent.Name):toBe("LandedTrailing")
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("opens an overlay from a top bar region in the composition's ScreenGui", {
			id = "native_composition::Composition::opens an overlay from a top bar region in the composition's ScreenGui",
			run = function()
				local engine, runtime, UI, gui = make()
				local T = engine.types
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local open = Compose.cell(false)
				runtime.mount(function()
					local Host = runtime.constructors
					return UI.Composition {
						gap = 8,
						padding = 0,
						UI.Region {
							Name = "Gear",
							zone = "topbar",
							rank = 1,
							leading = true,
							UI.Popover "Options" {
								isPresented = open,
								trigger = UI.Button "Gear" { label = "Options" },
								content = function()
									return Host.Frame { Name = "OptionsPanel" }
								end,
							},
						},
					}
				end, layer)
				engine.environment.poke(gui, "TopbarInset", T.Rect.new(164, 0, 844, 58))
				open:set(true)
				local panel = layer:FindFirstChild("OptionsPanel", true)
				Verify.expect(panel ~= nil):toBe(true)
				Verify.expect(panel:FindFirstAncestorWhichIsA("ScreenGui")):toBe(layer)
				runtime:dispose()
			end,
		})

		verifyHarness:case("hides its top bar strip while the composition or one of its ancestors is hidden", {
			id = "native_composition::Composition::hides its top bar strip while the composition or one of its ancestors is hidden",
			run = function()
				local engine, runtime, UI, gui = make()
				local T = engine.types
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local page = engine.new("Frame")
				page.Parent = layer
				local root, wallet
				runtime.mount(function()
					local Host = runtime.constructors
					wallet = UI.Region {
						Name = "Wallet",
						zone = "topbar",
						rank = 1,
						Host.Frame { Name = "WalletFull" },
					}
					root = UI.Composition { gap = 8, padding = 0, wallet }
					return root
				end, page)
				engine.environment.poke(gui, "TopbarInset", T.Rect.new(164, 0, 844, 58))
				local strip = wallet:FindFirstAncestorWhichIsA("ScreenGui")
				Verify.expect(strip.Name):toBe("CompositionTopbar")
				Verify.expect(strip.Enabled):toBe(true)
				page.Visible = false
				Verify.expect(strip.Enabled):toBe(false)
				page.Visible = true
				Verify.expect(strip.Enabled):toBe(true)
				root.Visible = false
				Verify.expect(strip.Enabled):toBe(false)
				root.Visible = true
				Verify.expect(strip.Enabled):toBe(true)
				layer.Enabled = false
				Verify.expect(strip.Enabled):toBe(false)
				layer.Enabled = true
				Verify.expect(strip.Enabled):toBe(true)
				local closed = engine.new("Frame")
				closed.Visible = false
				closed.Parent = layer
				page.Parent = closed
				Verify.expect(strip.Enabled):toBe(false)
				Verify.expect(wallet:FindFirstAncestorWhichIsA("ScreenGui")):toBe(strip)
				page.Parent = layer
				Verify.expect(strip.Enabled):toBe(true)
				closed.Visible = true
				closed.Visible = false
				Verify.expect(strip.Enabled):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("stacks a center-lane zone under its corners when no region can give way", {
			id = "native_composition::Composition::stacks a center-lane zone under its corners when no region can give way",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local function wide(x: number, y: number)
					return { x = x, y = y }
				end
				local item: Declared =
					{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { wide(92, 149) } }
				local map: Declared =
					{ zone = "topRight" :: "topRight", rank = 1, mayDrop = false, sizes = { wide(96, 96) } }
				local panel: Declared = { zone = "top" :: "top", rank = 1, mayDrop = false, sizes = { wide(200, 150) } }
				local forms, _, shift = resolver.resolve(327, 628, 8, { item, map, panel })
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(1)
				Verify.expect(forms[3]):toBe(1)
				Verify.expect(shift.top):toBe(157)
				Verify.expect(shift.bottom):toBe(0)
				local list: Declared = { zone = "left" :: "left", rank = 4, mayDrop = true, sizes = { wide(60, 94) } }
				forms, _, shift = resolver.resolve(327, 628, 8, { item, map, panel, list })
				Verify.expect(forms[4]):toBe(0)
				Verify.expect(shift.top):toBe(157)
				local narrow: Declared = { zone = "top" :: "top", rank = 1, mayDrop = false, sizes = { wide(100, 40) } }
				forms, _, shift = resolver.resolve(327, 628, 8, { item, map, narrow })
				Verify.expect(shift.top):toBe(0)
				local tip: Declared = { zone = "top" :: "top", rank = 2, mayDrop = true, sizes = { wide(200, 60) } }
				forms, _, shift = resolver.resolve(327, 628, 8, { item, map, tip })
				Verify.expect(forms[3]):toBe(0)
				Verify.expect(shift.top):toBe(0)
				local banner: Declared = { zone = "top" :: "top", rank = 1, mayDrop = false, sizes = { wide(400, 60) } }
				local overflow
				forms, _, shift, overflow = resolver.resolve(327, 628, 8, { item, map, banner })
				Verify.expect(shift.top):toBe(157)
				Verify.expect(#overflow):toBe(1)
				Verify.expect(overflow[1]):toBe(3)

				local engine, runtime, UI = make()
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local root: Frame
				runtime.mount(function()
					local Host = runtime.constructors
					root = UI.Composition {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region { Name = "Item", zone = "topLeft", rank = 1, Host.Frame { Name = "ItemFull" } },
						UI.Region { Name = "Map", zone = "topRight", rank = 1, Host.Frame { Name = "MapFull" } },
						UI.Region { Name = "Panel", zone = "top", rank = 1, Host.Frame { Name = "PanelFull" } },
					}
					return root
				end, layer)
				sized(engine, root:FindFirstChild("ItemFull", true), 92, 149)
				sized(engine, root:FindFirstChild("MapFull", true), 96, 96)
				sized(engine, root:FindFirstChild("PanelFull", true), 200, 150)
				sized(engine, root:FindFirstChild("Zones"), 327, 628)
				local top = root:FindFirstChild("Top", true) :: Frame
				Verify.expect(top.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 157))
				sized(engine, root:FindFirstChild("PanelFull", true), 100, 40)
				Verify.expect(top.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 0))
				runtime:dispose()
			end,
		})

		verifyHarness:case("moves a center-lane zone beside its row's one occupied corner before it stacks the zone", {
			id = "native_composition::Composition::moves a center-lane zone beside its row's one occupied corner before it stacks the zone",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local function wide(x: number, y: number)
					return { x = x, y = y }
				end
				local wallet: Declared =
					{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { wide(103, 102) } }
				local goals: Declared = {
					zone = "top" :: "top",
					rank = 2,
					mayDrop = false,
					sizes = { wide(308, 27), wide(180, 27), wide(308, 31), wide(180, 27) },
				}
				local forms, _, shift, overflow = resolver.resolve(373, 688, 8, { wallet, goals })
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(2)
				Verify.expect(shift.top):toBe(0)
				Verify.expect(shift.leanTop):toBe(55.5)
				Verify.expect(#overflow):toBe(0)
				local map: Declared =
					{ zone = "topRight" :: "topRight", rank = 1, mayDrop = false, sizes = { wide(44, 44) } }
				forms, _, shift = resolver.resolve(373, 688, 8, { wallet, goals, map })
				Verify.expect(forms[2]):toBe(1)
				Verify.expect(shift.top):toBe(110)
				Verify.expect(shift.leanTop):toBe(0)
				local mirrored: Declared =
					{ zone = "bottomRight" :: "bottomRight", rank = 1, mayDrop = false, sizes = { wide(70, 70) } }
				local notice: Declared =
					{ zone = "bottom" :: "bottom", rank = 3, mayDrop = false, sizes = { wide(260, 40) } }
				forms, _, shift = resolver.resolve(373, 688, 8, { mirrored, notice })
				Verify.expect(forms[2]):toBe(1)
				Verify.expect(shift.bottom):toBe(0)
				Verify.expect(shift.leanBottom):toBe(-39)
				local roomy: Declared = { zone = "top" :: "top", rank = 2, mayDrop = false, sizes = { wide(140, 27) } }
				forms, _, shift = resolver.resolve(373, 688, 8, { wallet, roomy })
				Verify.expect(shift.leanTop):toBe(0)

				local engine, runtime, UI = make()
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local root: Frame
				runtime.mount(function()
					local Host = runtime.constructors
					root = UI.Composition {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region { Name = "Wallet", zone = "topLeft", rank = 1, Host.Frame { Name = "WalletFull" } },
						UI.Region {
							Name = "Goals",
							zone = "top",
							rank = 2,
							Host.Frame { Name = "GoalsWide" },
							Host.Frame { Name = "GoalsLine" },
						},
					}
					return root
				end, layer)
				sized(engine, root:FindFirstChild("WalletFull", true), 103, 102)
				sized(engine, root:FindFirstChild("GoalsWide", true), 308, 27)
				sized(engine, root:FindFirstChild("GoalsLine", true), 180, 27)
				sized(engine, root:FindFirstChild("Zones"), 373, 688)
				local top = root:FindFirstChild("Top", true) :: Frame
				Verify.expect(top.Position):toBe(engine.types.UDim2.new(0.5, 55.5, 0, 0))
				sized(engine, root:FindFirstChild("GoalsLine", true), 120, 27)
				sized(engine, root:FindFirstChild("GoalsWide", true), 140, 27)
				Verify.expect(top.Position):toBe(engine.types.UDim2.new(0.5, 0, 0, 0))
				runtime:dispose()
			end,
		})

		verifyHarness:case("discloses a stepped-down region's richest content in context, anchored at the region", {
			id = "native_composition::Composition::discloses a stepped-down region's richest content in context, anchored at the region",
			run = function()
				local overlay = require("./lib/overlay_world")
				local form = Compose.cell(1)
				local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Composition "Hud" {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region "Rounds" {
							zone = "topLeft" :: "topLeft",
							rank = 1,
							Host.Frame { Name = "RoundsFull" },
						} :: unknown,
						UI.Region "Tasks" {
							zone = "left" :: "left",
							rank = 2,
							form = form,
							expand = function(): Instance
								return Host.TextLabel "TasksRich" { Text = "Win a round" }
							end,
							Host.Frame { Name = "TasksFull" } :: unknown,
							Host.Frame { Name = "TasksChip" },
						},
					}
				end)
				for name, size in
					{ RoundsFull = { 120, 44 }, TasksFull = { 240, 130 }, TasksChip = { 90, 30 } } :: { [string]: { number } }
				do
					w.size(w.find(name), size[1], size[2])
				end
				local zones = w.find("Zones")
				w.size(zones, 800, 400)
				local cover = w.find("Tasks"):FindFirstChild("Expand")
				Verify.expect((form:peek())):toBe(1)
				Verify.expect(cover.Visible):toBe(false)
				w.size(zones, 800, 150)
				Verify.expect((form:peek())):toBe(2)
				Verify.expect(cover.Visible):toBe(true)
				Verify.expect(cover.ZIndex < 0):toBe(true)
				Verify.expect(w.find("Tasks").AutomaticSize):toBe(w.Enum.AutomaticSize.None)
				Verify.expect(w.find("Tasks").Size):toBe(w.engine.types.UDim2.fromOffset(90, 44))
				Verify.expect(cover.Size):toBe(w.engine.types.UDim2.fromScale(1, 1))
				cover.Activated:Fire()
				Verify.expect(w.find("TasksRich") ~= nil):toBe(true)
				Verify.expect((w.find("ExpandModal"):GetAttribute("FacetRoute"))):toBe("popover")
				w.size(zones, 800, 400)
				Verify.expect((form:peek())):toBe(1)
				Verify.expect((w.find("TasksRich"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case(
			"leaves a Show hidden disc in place of a dropped region that can reveal, unless reveal is off",
			{
				id = "native_composition::Composition::leaves a Show hidden disc in place of a dropped region that can reveal, unless reveal is off",
				run = function()
					local overlay = require("./lib/overlay_world")
					for _, reveal in { true, false } do
						local form = Compose.cell(1)
						local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.Composition "Hud" {
								gap = 8,
								padding = 0,
								topbar = false,
								UI.Region "Rounds" {
									zone = "topLeft" :: "topLeft",
									rank = 1,
									Host.Frame { Name = "RoundsFull" },
								} :: unknown,
								UI.Region "Feed" {
									zone = "left" :: "left",
									rank = 2,
									mayDrop = true,
									reveal = if reveal then nil else false,
									form = form,
									expand = function(): Instance
										return Host.TextLabel "FeedRich" { Text = "Ravi eliminated Mo" }
									end,
									Host.Frame { Name = "FeedFull" },
								},
							}
						end)
						w.size(w.find("RoundsFull"), 120, 44)
						w.size(w.find("FeedFull"), 240, 130)
						local disc = w.find("Reveal")
						Verify.expect(disc ~= nil):toBe(reveal)
						if disc then
							w.size(disc, 28, 20)
						end
						local zones = w.find("Zones")
						w.size(zones, 800, 400)
						Verify.expect((form:peek())):toBe(1)
						w.size(zones, 800, 200)
						Verify.expect((form:peek())):toBe(if reveal then 2 else 0)
						if disc then
							Verify.expect(disc.Parent.Visible):toBe(true)
							Verify.expect(w.find("Feed"):FindFirstChild("Expand").Visible):toBe(true)
							w.find("Feed"):FindFirstChild("Expand").Activated:Fire()
							Verify.expect(w.find("FeedRich") ~= nil):toBe(true)
							w.size(zones, 800, 400)
							Verify.expect((w.find("FeedRich"))):toBeNil()
						end
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"reveals a dropped region's own content in place when it has no expand, and puts the same node back",
			{
				id = "native_composition::Composition::reveals a dropped region's own content in place when it has no expand, and puts the same node back",
				run = function()
					local overlay = require("./lib/overlay_world")
					local form = Compose.cell(1)
					local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Composition "Hud" {
							gap = 8,
							padding = 0,
							topbar = false,
							UI.Region "Rounds" {
								zone = "topLeft" :: "topLeft",
								rank = 1,
								Host.Frame { Name = "RoundsFull" },
							} :: unknown,
							UI.Region "Feed" {
								zone = "left" :: "left",
								rank = 2,
								mayDrop = true,
								form = form,
								Host.Frame { Name = "FeedFull" },
							},
						}
					end)
					local feed = w.find("FeedFull")
					local home = feed.Parent
					w.size(w.find("RoundsFull"), 120, 44)
					w.size(feed, 240, 130)
					w.size(w.find("Reveal"), 28, 20)
					local zones = w.find("Zones")
					w.size(zones, 800, 400)
					w.size(zones, 800, 200)
					Verify.expect((form:peek())):toBe(2)
					local target = w.find("Feed"):FindFirstChild("Expand")
					Verify.expect(target.Visible):toBe(true)
					target.Activated:Fire()
					Verify.expect(w.find("ExpandModal") ~= nil):toBe(true)
					Verify.expect(feed.Parent.Name):toBe("Hosted")
					Verify.expect((feed:IsDescendantOf(w.find("ExpandModal")))):toBe(true)
					w.size(feed, 200, 100)
					w.size(zones, 800, 400)
					Verify.expect((form:peek())):toBe(1)
					Verify.expect(feed.Parent):toBe(home)
					Verify.expect(feed.Parent ~= nil and home.Visible):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"gathers a zone's dropped regions behind one hit-floor badge beside the zone, outside its flow",
			{
				id = "native_composition::Composition::gathers a zone's dropped regions behind one hit-floor badge beside the zone, outside its flow",
				run = function()
					local overlay = require("./lib/overlay_world")
					for _, reveal in { true, false } do
						local feedForm, stayForm = Compose.cell(1), Compose.cell(1)
						local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.Composition "Hud" {
								gap = 8,
								padding = 0,
								topbar = false,
								UI.Region "Stay" {
									zone = "left" :: "left",
									rank = 1,
									form = stayForm,
									Host.Frame { Name = "StayFull" },
								} :: unknown,
								UI.Region "Feed" {
									zone = "left" :: "left",
									rank = 2,
									mayDrop = true,
									reveal = if reveal then nil else false,
									form = feedForm,
									Host.Frame { Name = "FeedFull" },
								},
							}
						end)
						local feed = w.find("FeedFull")
						local home = feed.Parent
						w.size(w.find("StayFull"), 100, 60)
						w.size(feed, 120, 60)
						local badge = w.find("Reveal")
						if badge then
							w.size(badge, 28, 60)
						end
						local zones = w.find("Zones")
						w.size(zones, 800, 400)
						local target = w.find("ZoneRevealLeft")
						Verify.expect(target ~= nil):toBe(reveal)
						w.size(zones, 800, 100)
						Verify.expect((feedForm:peek())):toBe(0)
						if target then
							local left = w.find("Left")
							w.size(left, 100, 60)
							Verify.expect(target.Visible):toBe(true)
							Verify.expect(target.Parent):toBe(zones)
							Verify.expect(target.Size.X.Offset >= 44 and target.Size.Y.Offset >= 44):toBe(true)
							Verify.expect(target.Position.X.Offset >= 100):toBe(true)
							Verify.expect(target.AnchorPoint.X):toBe(0)
							target.Activated:Fire()
							Verify.expect((feed:IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
							w.size(zones, 800, 400)
							Verify.expect((feedForm:peek())):toBe(1)
							Verify.expect(feed.Parent):toBe(home)
							Verify.expect(target.Visible):toBe(false)
						end
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"keeps the zone's hidden popover open while another region in the zone steps a visible form",
			{
				id = "native_composition::Composition::keeps the zone's hidden popover open while another region in the zone steps a visible form",
				run = function()
					local overlay = require("./lib/overlay_world")
					local feedForm, otherForm = Compose.cell(1), Compose.cell(1)
					local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Composition "Hud" {
							gap = 8,
							padding = 0,
							topbar = false,
							UI.Region "Other" {
								zone = "left" :: "left",
								rank = 1,
								mayDrop = true,
								form = otherForm,
								Host.Frame { Name = "OtherFull" } :: unknown,
								Host.Frame { Name = "OtherChip" },
							} :: unknown,
							UI.Region "Feed" {
								zone = "left" :: "left",
								rank = 2,
								mayDrop = true,
								form = feedForm,
								Host.Frame { Name = "FeedFull" },
							},
						}
					end)
					w.size(w.find("OtherFull"), 100, 60)
					w.size(w.find("OtherChip"), 40, 40)
					w.size(w.find("FeedFull"), 120, 60)
					for _, badge in
						{
							w.find("Other"):FindFirstChild("Reveal", true),
							w.find("Feed"):FindFirstChild("Reveal", true),
						}
					do
						w.size(badge, 28, 28)
					end
					local zones = w.find("Zones")
					w.size(zones, 800, 400)
					w.size(zones, 800, 90)
					Verify.expect(`{otherForm:peek()} {feedForm:peek()}`):toBe("1 0")
					w.size(w.find("Left"), 100, 60)
					w.find("ZoneRevealLeft").Activated:Fire()
					Verify.expect((w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
					w.size(zones, 800, 50)
					Verify.expect(`{otherForm:peek()} {feedForm:peek()}`):toBe("2 0")
					Verify.expect((w.find("FeedFull"):IsDescendantOf(w.find("HiddenFeed")))):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("keeps borrowed region content in its popover until the exit finishes", {
			id = "native_composition::Composition::keeps borrowed region content in its popover until the exit finishes",
			run = function()
				local overlay = require("./lib/overlay_world")
				local w: any = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Composition "Hud" {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region "Tasks" {
							zone = "left" :: "left",
							rank = 1,
							Host.Frame { Name = "TasksFull" },
							Host.Frame { Name = "TasksChip" },
						},
					}
				end, { motionLevel = "normal" }, { runService = true })
				local full = w.find("TasksFull")
				local home = full.Parent
				w.size(full, 240, 130)
				w.size(w.find("TasksChip"), 90, 30)
				w.size(w.find("Zones"), 200, 100)
				w.find("Expand").Activated:Fire()
				w.advance(1, 60)
				local modal = w.find("ExpandModal")
				Verify.expect((full:IsDescendantOf(modal))):toBe(true)
				w.find("DismissTarget").Activated:Fire()
				Verify.expect((full:IsDescendantOf(modal))):toBe(true)
				w.advance(1 / 60)
				Verify.expect((full:IsDescendantOf(modal))):toBe(true)
				w.advance(1, 60)
				Verify.expect(full.Parent):toBe(home)
				Verify.expect((w.find("ExpandModal"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("lets a corner zone use the row width that an empty center and the other corner leave", {
			id = "native_composition::Composition::lets a corner zone use the row width that an empty center and the other corner leave",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local wallet: Declared = {
					zone = "topLeft" :: "topLeft",
					rank = 2,
					mayDrop = false,
					sizes = { { x = 200, y = 90 }, { x = 110, y = 40 } },
				}
				local dock: Declared =
					{ zone = "topRight" :: "topRight", rank = 1, mayDrop = false, sizes = { { x = 120, y = 60 } } }
				Verify.expect(resolver.resolve(390, 800, 8, { wallet, dock })[1]):toBe(1)
				local banner: Declared =
					{ zone = "top" :: "top", rank = 3, mayDrop = true, sizes = { { x = 60, y = 30 } } }
				Verify.expect(resolver.resolve(390, 800, 8, { wallet, dock, banner })[1]):toBe(2)
				local side: Declared =
					{ zone = "left" :: "left", rank = 2, mayDrop = true, sizes = { { x = 200, y = 60 } } }
				Verify.expect(resolver.resolve(390, 800, 8, { side })[1]):toBe(0)
			end,
		})
		verifyHarness:case("lets a center-lane zone use the width that the side zones of its row leave free", {
			id = "native_composition::Composition::lets a center-lane zone use the width that the side zones of its row leave free",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local function wide(x: number, y: number)
					return { x = x, y = y }
				end
				local radio: Declared = { zone = "top" :: "top", rank = 2, mayDrop = true, sizes = { wide(330, 60) } }
				local corner: Declared =
					{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { wide(180, 120) } }
				Verify.expect(resolver.resolve(749, 381, 8, { radio, corner })[1]):toBe(1)
				local crowded: Declared =
					{ zone = "topRight" :: "topRight", rank = 1, mayDrop = false, sizes = { wide(240, 60) } }
				Verify.expect(resolver.resolve(749, 381, 8, { radio, corner, crowded })[1]):toBe(0)
				local below: Declared =
					{ zone = "bottomLeft" :: "bottomLeft", rank = 1, mayDrop = false, sizes = { wide(240, 60) } }
				Verify.expect(resolver.resolve(749, 381, 8, { radio, corner, below })[1]):toBe(1)
				local side: Declared = { zone = "left" :: "left", rank = 2, mayDrop = true, sizes = { wide(330, 60) } }
				Verify.expect(resolver.resolve(749, 381, 8, { side })[1]):toBe(0)
			end,
		})

		verifyHarness:case("steps a lower-rank side region down before a center region that its row squeezes", {
			id = "native_composition::Composition::steps a lower-rank side region down before a center region that its row squeezes",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local function wide(x: number, y: number)
					return { x = x, y = y }
				end
				local bar: Declared =
					{ zone = "top" :: "top", rank = 1, mayDrop = false, sizes = { wide(200, 90), wide(170, 80) } }
				local radio: Declared =
					{ zone = "topLeft" :: "topLeft", rank = 3, mayDrop = true, sizes = { wide(120, 50), wide(60, 50) } }
				local forms = resolver.resolve(390, 800, 8, { bar, radio })
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(2)
				local score: Declared =
					{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { wide(120, 50) } }
				local tip: Declared =
					{ zone = "top" :: "top", rank = 2, mayDrop = true, sizes = { wide(200, 90), wide(120, 60) } }
				forms = resolver.resolve(390, 800, 8, { tip, score })
				Verify.expect(forms[1]):toBe(2)
				Verify.expect(forms[2]):toBe(1)
				local banner: Declared = { zone = "top" :: "top", rank = 1, mayDrop = false, sizes = { wide(500, 90) } }
				forms = resolver.resolve(390, 800, 8, { banner, radio })
				Verify.expect(forms[2]):toBe(1)
			end,
		})

		verifyHarness:case("lets a center-lane zone use the full width when both side zones of its row are empty", {
			id = "native_composition::Composition::lets a center-lane zone use the full width when both side zones of its row are empty",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local function wide(x: number, y: number)
					return { x = x, y = y }
				end
				local bar: Declared =
					{ zone = "bottom" :: "bottom", rank = 3, mayDrop = false, sizes = { wide(361, 46) } }
				local forms, _, shift, overflow = resolver.resolve(369, 687, 8, { bar })
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(#overflow):toBe(0)
				Verify.expect(shift.bottom):toBe(0)
				local corner: Declared =
					{ zone = "bottomRight" :: "bottomRight", rank = 1, mayDrop = false, sizes = { wide(60, 60) } }
				forms, _, shift, overflow = resolver.resolve(369, 687, 8, { bar, corner })
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(1)
				Verify.expect(shift.bottom):toBe(68)
				Verify.expect(#overflow):toBe(0)
				local chip: Declared =
					{ zone = "bottomLeft" :: "bottomLeft", rank = 4, mayDrop = true, sizes = { wide(60, 60) } }
				forms, _, shift, overflow = resolver.resolve(369, 687, 8, { bar, chip })
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(0)
				Verify.expect(shift.bottom):toBe(0)
				Verify.expect(#overflow):toBe(0)

				local declared: { Declared } = {
					bar,
					{
						zone = "bottom" :: "bottom",
						rank = 2,
						mayDrop = false,
						sizes = { wide(1256, 73), wide(375, 50), wide(244, 73) },
					},
					{
						zone = "center" :: "center",
						rank = 1,
						mayDrop = false,
						sizes = { wide(560, 140), wide(300, 140) },
					},
					{ zone = "topLeft" :: "topLeft", rank = 2, mayDrop = false, sizes = { wide(52, 52) } },
					{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { wide(100, 39) } },
					{
						zone = "topRight" :: "topRight",
						rank = 2,
						mayDrop = true,
						sizes = { wide(96, 96), wide(60, 60) },
					},
					{ zone = "topbar" :: "topbar", rank = 1, mayDrop = false, sizes = { wide(0, 0) } },
				}
				forms, _, shift, overflow = resolver.resolve(369, 687, 8, declared, { x = 221, y = 44 })
				Verify.expect(#overflow):toBe(0)
				Verify.expect(shift.bottom):toBe(0)
				Verify.expect(forms[1]):toBe(1)
				Verify.expect(forms[2]):toBe(3)
				Verify.expect(forms[3]):toBe(2)
			end,
		})

		verifyHarness:case(
			"lays the top and bottom zones out side by side and wraps a region only when the row is full",
			{
				id = "native_composition::Composition::lays the top and bottom zones out side by side and wraps a region only when the row is full",
				run = function()
					local resolver = require("../src/ui/composition_resolve")
					type Declared = resolver.Declared
					local function wide(x: number, y: number)
						return { x = x, y = y }
					end
					local planet: Declared =
						{ zone = "top" :: "top", rank = 1, mayDrop = false, sizes = { wide(230, 60), wide(110, 30) } }
					local order: Declared =
						{ zone = "top" :: "top", rank = 3, mayDrop = true, sizes = { wide(240, 60), wide(120, 30) } }
					local wallet: Declared =
						{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { wide(150, 90) } }
					local menu: Declared =
						{ zone = "topRight" :: "topRight", rank = 2, mayDrop = false, sizes = { wide(44, 44) } }
					local forms, _, _, overflow, rows = resolver.resolve(1280, 720, 8, { planet, order, wallet, menu })
					Verify.expect(rows.top):toBe(478)
					Verify.expect(rows.bottom):toBe(0)
					Verify.expect(forms[1]):toBe(1)
					Verify.expect(forms[2]):toBe(1)
					Verify.expect(#overflow):toBe(0)
					local _, _, _, _, narrow = resolver.resolve(400, 900, 8, { planet, order })
					Verify.expect(narrow.top):toBe(240)
					local view: Declared =
						{ zone = "center" :: "center", rank = 2, mayDrop = false, sizes = { wide(300, 200) } }
					forms = resolver.resolve(1280, 400, 8, { planet, order, wallet, menu, view })
					Verify.expect(forms[1]):toBe(1)
					Verify.expect(forms[2]):toBe(1)
					local hint: Declared =
						{ zone = "bottom" :: "bottom", rank = 4, mayDrop = true, sizes = { wide(300, 24) } }
					local notice: Declared =
						{ zone = "bottom" :: "bottom", rank = 5, mayDrop = true, sizes = { wide(200, 40) } }
					local _, _, _, _, bottom = resolver.resolve(1280, 720, 8, { hint, notice })
					Verify.expect(bottom.bottom):toBe(508)

					local engine, runtime, UI = make()
					local layer = engine.new("ScreenGui")
					layer.Parent = engine.new("Folder")
					local root: Frame
					runtime.mount(function()
						local Host = runtime.constructors
						root = UI.Composition {
							gap = 8,
							padding = 0,
							topbar = false,
							UI.Region { Name = "Planet", zone = "top", rank = 1, Host.Frame { Name = "PlanetFull" } },
							UI.Region { Name = "Duel", zone = "top", rank = 2, Host.Frame { Name = "DuelFull" } },
							UI.Region { Name = "Order", zone = "top", rank = 3, Host.Frame { Name = "OrderFull" } },
							UI.Region { Name = "Wallet", zone = "topLeft", rank = 1, Host.Frame { Name = "WalletFull" } },
						}
						return root
					end, layer)
					sized(engine, root:FindFirstChild("PlanetFull", true), 230, 60)
					sized(engine, root:FindFirstChild("OrderFull", true), 240, 60)
					sized(engine, root:FindFirstChild("WalletFull", true), 150, 90)
					sized(engine, root:FindFirstChild("Zones"), 1280, 720)
					local top = root:FindFirstChild("Top", true) :: Frame
					local list = top:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout
					local T = engine.types
					Verify.expect(list.FillDirection):toBe(T.Enum.FillDirection.Horizontal)
					Verify.expect(list.Wraps):toBe(true)
					Verify.expect(top.Size):toBe(T.UDim2.fromOffset(478, 0))
					Verify.expect(top.AutomaticSize):toBe(T.Enum.AutomaticSize.Y)
					local duel = top:FindFirstChild("Duel") :: Frame
					Verify.expect(duel.Visible):toBe(false)
					Verify.expect((top:FindFirstChild("Planet") :: Frame).Visible):toBe(true)
					sized(engine, root:FindFirstChild("DuelFull", true), 100, 40)
					Verify.expect(duel.Visible):toBe(true)
					sized(engine, root:FindFirstChild("DuelFull", true), 0, 0)
					Verify.expect(duel.Visible):toBe(false)
					local left = root:FindFirstChild("TopLeft", true) :: Frame
					local column = left:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout
					Verify.expect(column.FillDirection):toBe(T.Enum.FillDirection.Vertical)
					Verify.expect(column.Wraps):toBe(false)
					sized(engine, root:FindFirstChild("Zones"), 600, 900)
					Verify.expect(top.Size):toBe(T.UDim2.fromOffset(240, 0))
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("gives the regions of a top row the height of the tallest one unless rows is fit", {
			id = "native_composition::Composition::gives the regions of a top row the height of the tallest one unless rows is fit",
			run = function()
				local engine, runtime, UI = make()
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local rows = Compose.cell("match" :: "match" | "fit")
				local root: Frame
				runtime.mount(function()
					local Host = runtime.constructors
					root = UI.Composition {
						gap = 8,
						padding = 0,
						topbar = false,
						rows = rows,
						UI.Region {
							Name = "Planet",
							zone = "top",
							rank = 1,
							Host.Frame {
								Name = "PlanetFull",
								AutomaticSize = engine.types.Enum.AutomaticSize.XY,
								Host.Frame { Name = "PlanetInner" },
							},
						},
						UI.Region {
							Name = "Order",
							zone = "top",
							rank = 2,
							Host.Frame {
								Name = "OrderFull",
								AutomaticSize = engine.types.Enum.AutomaticSize.XY,
								Host.Frame { Name = "OrderInner" },
							},
						},
					}
					return root
				end, layer)
				local planet = assert(root:FindFirstChild("PlanetFull", true))
				local order = assert(root:FindFirstChild("OrderFull", true))
				local function lift(node: Instance): number
					local floor = node:FindFirstChild("Lift") :: UISizeConstraint?
					return if floor then floor.MinSize.Y else 0
				end
				local function size(node: Instance, width: number, inner: number, outer: number)
					sized(engine, assert(node:FindFirstChildWhichIsA("Frame")), width, inner)
					sized(engine, node, width, outer)
				end
				size(planet, 230, 60, 60)
				size(order, 240, 40, 40)
				sized(engine, assert(root:FindFirstChild("Zones")), 1280, 720)
				Verify.expect(lift(order)):toBe(60)
				Verify.expect(lift(planet)):toBe(0)
				size(order, 240, 40, 60)
				Verify.expect(lift(order)):toBe(60)
				size(planet, 230, 30, 30)
				Verify.expect(lift(planet)):toBe(40)
				Verify.expect(lift(order)):toBe(0)
				rows:set("fit")
				Verify.expect(lift(planet)):toBe(0)
				Verify.expect(lift(order)):toBe(0)
				runtime:dispose()
			end,
		})

		verifyHarness:case("lists the zones that hold a visible region outside the top bar strip", {
			id = "native_composition::Composition::lists the zones that hold a visible region outside the top bar strip",
			run = function()
				local resolver = require("../src/ui/composition_resolve")
				type Declared = resolver.Declared
				local declared: { Declared } = {
					{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { { x = 120, y = 44 } } },
					{ zone = "topRight" :: "topRight", rank = 1, mayDrop = true, sizes = { { x = 96, y = 96 } } },
					{ zone = "bottom" :: "bottom", rank = 1, mayDrop = false, sizes = { { x = 0, y = 0 } } },
					{ zone = "topbar" :: "topbar", rank = 1, mayDrop = false, sizes = { { x = 44, y = 44 } } },
				}
				local zones = resolver.occupied(declared, { 1, 0, 1, 1 }, { false, false, false, false }, true)
				Verify.expect(zones.topLeft):toBe(true)
				Verify.expect(zones.topRight):toBeNil()
				Verify.expect(zones.bottom):toBeNil()
				Verify.expect(zones.top):toBeNil()
				zones = resolver.occupied(declared, { 1, 0, 1, 1 }, { false, false, false, true }, true)
				Verify.expect(zones.top):toBe(true)
			end,
		})

		verifyHarness:case("warns once when two Compositions on one screen place regions in the same zone", {
			id = "native_composition::Composition::warns once when two Compositions on one screen place regions in the same zone",
			run = function()
				local env = (getfenv(require("../src/ui/composition")) :: unknown) :: { [string]: unknown }
				local warnings: { string } = {}
				env.warn = function(...)
					local parts = {}
					for index = 1, select("#", ...) do
						table.insert(parts, tostring((select(index, ...))))
					end
					table.insert(warnings, table.concat(parts, " "))
				end
				local ok, err = pcall(function()
					local engine, runtime, UI = make()
					local screens = engine.new("Folder")
					local elsewhere = engine.new("Folder")
					local function hud(name: string, zone: "topLeft" | "topRight" | "bottom", parent: unknown)
						local layer = engine.new("ScreenGui")
						layer.Parent = parent
						local root: Frame
						local stop = runtime.mount(function()
							local Host = runtime.constructors
							root = UI.Composition(name) {
								gap = 8,
								padding = 0,
								topbar = false,
								UI.Region {
									Name = name .. "Region",
									zone = zone,
									rank = 1,
									Host.Frame {
										Name = name .. "Full",
									},
								},
							}
							return root
						end, layer)
						sized(engine, root:FindFirstChild(name .. "Full", true), 120, 44)
						sized(engine, root:FindFirstChild("Zones"), 844, 390)
						return root, layer, stop
					end
					local _, _, stopScore = hud("Score", "topLeft", screens)
					local _, _, stopChat = hud("Chat", "topLeft", screens)
					hud("Map", "topRight", screens)
					hud("Other", "topLeft", elsewhere)
					engine.heartbeat:Fire(2.5)
					Verify.expect(#warnings):toBe(1)
					Verify.expect(warnings[1]):toBe(
						"Facet Composition: Compositions 'Chat' and 'Score' both place regions in the topLeft zone of one screen. Each Composition lays out only its own regions, so the regions can overlap. Keep the HUD of a screen in one Composition"
					)
					local _, hiddenLayer = hud("Quest", "topRight", screens)
					hiddenLayer.Enabled = false
					local empty = hud("Toast", "bottom", screens)
					sized(engine, empty:FindFirstChild("ToastFull", true), 0, 0)
					hud("Banner", "bottom", screens)
					engine.heartbeat:Fire(2.5)
					Verify.expect(#warnings):toBe(1)
					hiddenLayer.Enabled = true
					engine.heartbeat:Fire(1)
					Verify.expect(#warnings):toBe(1)
					engine.heartbeat:Fire(1.5)
					Verify.expect(#warnings):toBe(2)
					Verify.expect(string.find(warnings[2], "'Quest' and 'Map'", 1, true) ~= nil):toBe(true)
					stopScore()
					stopChat()
					hud("Again", "topLeft", screens)
					engine.heartbeat:Fire(2.5)
					Verify.expect(#warnings):toBe(2)
					local _, movedLayer = hud("Moved", "bottom", elsewhere)
					movedLayer.Parent = screens
					engine.heartbeat:Fire(2.5)
					Verify.expect(#warnings):toBe(3)
					Verify.expect(string.find(warnings[3], "'Moved' and 'Banner'", 1, true) ~= nil):toBe(true)
					runtime:dispose()
				end)
				env.warn = nil
				if not ok then
					error(err, 0)
				end
			end,
		})

		verifyHarness:case("explains branch placement and reacts inside a stable Region form", function(t)
			local engine, runtime, UI = make()
			local Host: RobloxHost = runtime.constructors
			local shown = Compose.cell(false)
			local layer = engine.new("ScreenGui")
			local ok, message = pcall(function()
				runtime.mount(function()
					return UI.Composition {
						Compose.show(shown, function()
							return UI.Region { zone = "top", rank = 1, Host.Frame {} }
						end),
					}
				end, layer)
			end)
			t:expect(ok):toBe(false)
			t:expect(string.find(tostring(message), "Put Compose.show inside a stable Region form", 1, true) ~= nil)
				:toBe(true)
			runtime.mount(function()
				return UI.Composition {
					UI.Region "Controls" {
						zone = "top",
						rank = 1,
						Host.Frame "StableForm" {
							Compose.show(shown, function()
								return Host.Frame "DrivingControls" {}
							end),
						},
					},
				}
			end, layer)
			local stable = layer:FindFirstChild("StableForm", true)
			t:expect(stable ~= nil):toBe(true)
			t:expect(layer:FindFirstChild("DrivingControls", true)):toBe(nil)
			shown:set(true)
			t:expect(layer:FindFirstChild("DrivingControls", true).Parent):toBe(stable)
			shown:set(false)
			t:expect(layer:FindFirstChild("DrivingControls", true)):toBe(nil)
			t:expect(layer:FindFirstChild("StableForm", true)):toBe(stable)
			runtime:dispose()
		end)

		verifyHarness:case("reports invalid form values at the Region boundary", function(t)
			local candidates: { unknown } = { false, 42, "form", {}, function() end }
			for _, candidate in candidates do
				local engine, runtime, UI = make()
				local ok, message = pcall(function()
					runtime.mount(function()
						return UI.Region(({ zone = "top", rank = 1, candidate } :: unknown) :: LayoutProps.RegionProps)
					end, engine.new("ScreenGui"))
				end)
				runtime:dispose()
				t:expect(ok):toBe(false)
				t:expect(string.find(tostring(message), "Facet Region forms must be GuiObjects", 1, true) ~= nil)
					:toBe(true)
			end
		end)

		verifyHarness:case(
			"refuses an unknown anchor, a rank that is not a whole number, and a child that is not a Region",
			{
				id = "native_composition::Composition::refuses an unknown anchor, a rank that is not a whole number, and a child that is not a Region",
				run = function()
					local function refusal(body: (any, any) -> any): string
						local engine, runtime, UI = make()
						local ok, message = pcall(function()
							runtime.mount(function()
								return body(UI, runtime.constructors)
							end, engine.new("ScreenGui"))
						end)
						runtime:dispose()
						return if ok then "" else tostring(message)
					end
					Verify.expect(string.find(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.Region { zone = "middle" :: any, rank = 1, Host.Frame {} }
						end),
						"zone",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect(string.find(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.Region { zone = "top" :: "top", rank = 1.5, Host.Frame {} }
						end),
						"rank",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect(string.find(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.Composition { Host.Frame {} }
						end),
						"UI.Region",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect(string.find(
						refusal(function(UI: FacetControls)
							return UI.Region { zone = "top" :: "top", rank = 1 }
						end),
						"form",
						1,
						true
					) ~= nil):toBe(true)
					Verify.expect((refusal(function(UI: FacetControls)
						return UI.Composition { UI.fill() }
					end))):toBe("")
				end,
			}
		)

		verifyHarness:case("lifts the bottom zones by the caption overhang so the row shares one baseline", function(t)
			local root, engine, stop = actionRow({ captions = true })
			local T = engine.types
			local left = root:FindFirstChild("BottomLeft", true) :: Frame
			local right = root:FindFirstChild("BottomRight", true) :: Frame
			t:expect(left.Position):toBe(T.UDim2.new(0, 0, 1, -18))
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			local function centre(zone: Frame): number
				return 700 * zone.Position.Y.Scale + zone.Position.Y.Offset - 44 * zone.AnchorPoint.Y + 22
			end
			t:expect(centre(left)):toBe(centre(right))
			t:expect(centre(left)):toBe(660)
			sized(engine, (root:FindFirstChild("Garage", true) :: TextButton):FindFirstChild("Caption"), 52, 20)
			t:expect(left.Position):toBe(T.UDim2.new(0, 0, 1, -24))
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -24))
			stop()
			root, engine, stop = actionRow({ captions = false })
			T = engine.types
			t:expect((root:FindFirstChild("BottomLeft", true) :: Frame).Position):toBe(T.UDim2.new(0, 0, 1, 0))
			t:expect((root:FindFirstChild("BottomRight", true) :: Frame).Position):toBe(T.UDim2.new(1, 0, 1, 0))
			stop()
		end)

		verifyHarness:case("drops the caption overhang of a bottom region that its author hides", function(t)
			local shown = Compose.cell(true)
			local root, engine, stop = actionRow({ captions = true, shown = shown })
			local T = engine.types
			local left = root:FindFirstChild("BottomLeft", true) :: Frame
			local right = root:FindFirstChild("BottomRight", true) :: Frame
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			shown:set(false)
			t:expect(left.Position):toBe(T.UDim2.new(0, 0, 1, 0))
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, 0))
			shown:set(true)
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			stop()
		end)

		verifyHarness:case("drops the caption overhang of a bottom region that gives way", function(t)
			local form = Compose.cell(1)
			local root, engine, stop = actionRow({ captions = true, mayDrop = true, reveal = false, form = form })
			local T = engine.types
			local right = root:FindFirstChild("BottomRight", true) :: Frame
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			sized(engine, root:FindFirstChild("Zones"), 240, 700)
			t:expect(form:peek()):toBe(0)
			t:expect(right.Position.Y.Offset):toBe(0)
			sized(engine, root:FindFirstChild("Zones"), 390, 700)
			t:expect(form:peek()):toBe(1)
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			stop()
		end)

		verifyHarness:case("drops the overhang of a caption that leaves the row or hides with its Button", function(t)
			local root, engine, stop = actionRow({ captions = true })
			local T = engine.types
			local right = root:FindFirstChild("BottomRight", true) :: Frame
			local caption = (root:FindFirstChild("Pass", true) :: TextButton):FindFirstChild("Caption") :: TextLabel
			caption.Parent = nil
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			local shop = root:FindFirstChild("Shop", true) :: TextButton
			shop.Visible = false
			t:expect(right.Position):toBe(T.UDim2.new(1, 0, 1, -18))
			local garage = root:FindFirstChild("Garage", true) :: TextButton
			garage.Visible = false
			t:expect(garage.Visible):toBe(false)
			t:expect(right.Position.Y.Offset):toBe(0)
			stop()
		end)

		verifyHarness:case("adds no room under a row whose own bottom padding already holds the captions", function(t)
			local root, engine, stop = actionRow({ captions = true, padding = { bottom = "l" } })
			local T = engine.types
			t:expect((root:FindFirstChild("BottomLeft", true) :: Frame).Position):toBe(T.UDim2.new(0, 0, 1, 0))
			t:expect((root:FindFirstChild("BottomRight", true) :: Frame).Position):toBe(T.UDim2.new(1, 0, 1, 0))
			local caption = (root:FindFirstChild("Shop", true) :: TextButton):FindFirstChild("Caption") :: TextLabel
			t:expect(caption.AbsolutePosition.Y + caption.AbsoluteSize.Y <= 700):toBe(true)
			stop()
		end)

		verifyHarness:case(
			"puts the action zone at the bottom centre when portrait and the bottom right otherwise",
			function(t)
				local engine, runtime, UI = make()
				local layer = engine.new("ScreenGui")
				layer.Parent = engine.new("Folder")
				local root: Frame
				runtime.mount(function()
					root = UI.Composition "Hud" {
						gap = 8,
						padding = 0,
						topbar = false,
						UI.Region "Status" { zone = "topLeft", rank = 2, UI.Text { text = "Level 4" } },
						UI.Region "Go" { zone = "action", rank = 1, UI.Button "Race" { label = "Race" } },
					}
					return root
				end, layer)
				sized(engine, root:FindFirstChild("Race", true), 160, 56)
				local go = root:FindFirstChild("Go", true) :: Frame
				sized(engine, root:FindFirstChild("Zones"), 390, 700)
				t:expect((go.Parent :: Instance).Name):toBe("Bottom")
				t:expect(go:GetAttribute("FacetForm")):toBe(1)
				sized(engine, root:FindFirstChild("Zones"), 844, 390)
				t:expect((go.Parent :: Instance).Name):toBe("BottomRight")
				t:expect(go:GetAttribute("FacetForm")):toBe(1)
				sized(engine, root:FindFirstChild("Zones"), 390, 700)
				t:expect((go.Parent :: Instance).Name):toBe("Bottom")
				runtime:dispose()
			end
		)

		verifyHarness:case("counts the caption overhang when it fits the bottom row under the zone above", function(t)
			local resolver = require("../src/ui/composition_resolve")
			type Declared = resolver.Declared
			local status: Declared =
				{ zone = "topLeft" :: "topLeft", rank = 1, mayDrop = false, sizes = { { x = 100, y = 44 } } }
			local actions: Declared = {
				zone = "bottomLeft" :: "bottomLeft",
				rank = 2,
				mayDrop = false,
				sizes = { { x = 156, y = 44 }, { x = 44, y = 44 } },
				hangs = { 18, 0 },
			}
			local race: Declared =
				{ zone = "bottomRight" :: "bottomRight", rank = 1, mayDrop = false, sizes = { { x = 80, y = 44 } } }
			local forms, _, shift = resolver.resolve(390, 120, 8, { status, actions, race })
			t:expect(forms[2]):toBe(1)
			t:expect(shift.hang):toBe(18)
			forms, _, shift = resolver.resolve(390, 110, 8, { status, actions, race })
			t:expect(forms[2]):toBe(2)
			t:expect(shift.hang):toBe(0)
			actions.hangs = nil
			forms, _, shift = resolver.resolve(390, 110, 8, { status, actions, race })
			t:expect(forms[2]):toBe(1)
			t:expect(shift.hang):toBe(0)
			forms, _, shift = resolver.resolve(390, 110, 8, { status, race })
			t:expect(shift.hang):toBe(0)
			t:expect(shift.bottom):toBe(0)
		end)
	end)
end
