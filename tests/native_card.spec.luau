--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local fadeKit = require("./lib/fade")
	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose
	local UDim2 = require("@lune/roblox").UDim2

	local function cardSpec(log: { string }, extra: { [any]: any }?): { [any]: any }
		local spec: { [any]: any } = {
			image = "rbxassetid://1",
			title = "Nebula Racers",
			caption = "Friends playing",
			onActivate = function()
				table.insert(log, "body")
			end,
			primaryAction = {
				label = "Play",
				onActivate = function()
					table.insert(log, "primary")
				end,
			},
			menu = {
				items = {
					{
						id = "hide",
						label = "Not interested",
						onSelect = function()
							table.insert(log, "hide")
						end,
					},
				},
			},
		}
		local additions: { [any]: any } = extra or {}
		for key, value in additions do
			spec[key] = value
		end
		return spec
	end

	local function mount(spec: { [any]: any }, options: { [string]: any }?, touch: boolean?): (any, any, { [any]: any })
		local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
		spec.controls = controls
		local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				Name = "Row",
				UI.Card("C")(spec) :: unknown,
				UI.Button({ Name = "Next", label = "Next" }),
			})
		end, options or { motionLevel = "none" })
		if touch then
			world.input.TouchEnabled = true
		end
		return world, world.find("C"), controls
	end

	local function attr(root: any, name: string): any
		return root:GetAttribute("Facet" .. name)
	end

	local function plate(world: any): any
		return world.find("Reveal")
	end

	local function primary(world: any): any
		return world.find("Primary")
	end

	local function more(world: any): any
		return world.find("More")
	end

	local function hover(root: any, inside: boolean)
		root:_fireSignal(if inside then "MouseEnter" else "MouseLeave")
	end

	local function settle(world: any, seconds: number)
		for _ = 1, math.ceil(seconds * 60) do
			world.engine.heartbeat:Fire(1 / 60)
		end
	end

	local function lift(root: any): string
		local scale = root:FindFirstChild("Lift").Scale
		local shadow = root:FindFirstChild("LiftShadow", true)
		return `scale {math.floor(scale * 1000 + 0.5) / 1000} shadow {shadow ~= nil and shadow.Enabled == true}`
	end

	local function gridWorld(count: number, twoGrids: boolean?, reduced: boolean?): any
		local log: { string } = {}
		local controlsByGrid: { [string]: { [string]: any } } = { A = {}, B = {} }
		local cardsByGrid: { [string]: { [string]: any } } = { A = {}, B = {} }
		local sources = {
			A = Compose.cell((function()
				local out = {}
				for index = 1, count do
					out[index] = { id = `i{index}`, title = `Game {index}` }
				end
				return out
			end)()),
			B = Compose.cell({ { id = "i1", title = "Other 1" }, { id = "i2", title = "Other 2" } }),
		}
		local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
			local function grid(name: string)
				local controls, cards = controlsByGrid[name], cardsByGrid[name]
				return UI.VirtualGrid({
					Name = name,
					from = sources[name],
					key = "id",
					columns = 3,
					itemSize = 280,
					gap = 16,
					onActivate = function(_item: any, key: string)
						local entry = controls[key]
						if entry then
							entry.enterActions()
						end
					end,
					render = function(current: any, _placement: any, key: string): GuiObject
						local entry = {}
						controls[key] = entry
						local card = UI.Card({
							Name = "Card",
							image = "rbxassetid://1",
							title = function(use: any)
								return use(current).title
							end,
							controls = entry,
							browseTarget = function()
								local node = cards[key]
								local content = if node then node.Parent else nil
								return if content then content:FindFirstChild("RowHit") else nil
							end,
							primaryAction = {
								label = "Play",
								onActivate = function()
									table.insert(log, `play:{key}`)
								end,
							},
							menu = {
								items = {
									{
										id = "hide",
										label = "Not interested",
										onSelect = function()
											table.insert(log, `hide:{key}`)
										end,
									},
								},
							},
						})
						cards[key] = card
						Compose.cleanup(function()
							if cards[key] == card then
								cards[key] = nil
								controls[key] = nil
							end
						end)
						return card
					end,
				})
			end
			local children: { any } = { grid("A") }
			if twoGrids then
				table.insert(children, grid("B"))
			end
			return Host.Frame({ Name = "Page", table.unpack((children :: unknown) :: { unknown }) })
		end, { motionLevel = if reduced ~= false then "none" else "normal" })
		for _, name in (if twoGrids then { "A", "B" } else { "A" }) :: { string } do
			local node = world.find(name)
			node.AbsoluteWindowSize = world.V2(900, 600)
		end
		return {
			world = world,
			log = log,
			sources = sources,
			controls = controlsByGrid,
			cards = cardsByGrid,
			hit = function(key: string, name: string?): any
				local card = cardsByGrid[name or "A"][key]
				return card and card.Parent and card.Parent:FindFirstChild("RowHit")
			end,
			card = function(key: string, name: string?): any
				return cardsByGrid[name or "A"][key]
			end,
		}
	end

	verifyHarness:suite("native Card", function()
		verifyHarness:case("refuses malformed specs before building anything", {
			id = "native_card::native Card::refuses malformed specs before building anything",
			run = function()
				local bad: { any } = {
					{ image = "", title = "T" },
					{ image = "rbxassetid://1" },
					{ image = "rbxassetid://1", title = "T", reveal = "hover" },
					{ image = "rbxassetid://1", title = "T", imageAspectRatio = 0 },
					{ image = "rbxassetid://1", title = "T", primaryAction = { label = "Play" } },
					{
						image = "rbxassetid://1",
						title = "T",
						primaryAction = { label = "P", onActivate = print, x = 1 },
					},
					{ image = "rbxassetid://1", title = "T", menu = { items = {}, extra = true } },
					{ image = "rbxassetid://1", title = "T", caption = 5 },
					{ image = "rbxassetid://1", title = "T", zIndex = 3 },
					{ title = "T" },
					{ title = "T", artwork = "rbxassetid://1" },
					{ image = "", title = "T", artwork = function() end },
				}
				for _, spec in bad do
					Verify.expect(worlds.mountError(function(UI: FacetControls)
						return UI.Card(spec)
					end) ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("keeps body, primary and More as sibling targets so one press runs one intent", {
			id = "native_card::native Card::keeps body, primary and More as sibling targets so one press runs one intent",
			run = function()
				local log: { string } = {}
				local world, root = mount(cardSpec(log))
				Verify.expect(world.find("Body").Parent):toBe(root)
				Verify.expect(fadeKit.layer(primary(world).Parent).Parent):toBe(root)
				Verify.expect((root:IsA("GuiButton"))):toBe(false)
				world.find("Body").Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("body")
				hover(root, true)
				primary(world).Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("body,primary")
				more(world).Activated:Fire()
				Verify.expect((attr(root, "MenuOpen"))):toBe(true)
				Verify.expect((table.concat(log, ","))):toBe("body,primary")
				world.stop()
			end,
		})

		verifyHarness:case("draws live artwork in the artwork frame and forwards the activating input to the body", {
			id = "native_card::native Card::draws live artwork in the artwork frame and forwards the activating input to the body",
			run = function()
				local inputs: { InputObject | string } = {}
				local released = 0
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Card "C" {
						title = "Afterlight",
						artwork = function(): GuiObject
							Compose.cleanup(function()
								released += 1
							end)
							return Host.ViewportFrame({ Name = "Preview" })
						end,
						onActivate = function(input: InputObject?)
							table.insert(inputs, (input or "none") :: any)
						end,
					}
				end, { motionLevel = "none" })
				local artwork = world.find("Artwork")
				local live = artwork:FindFirstChild("Preview")
				Verify.expect(artwork.Image):toBe("")
				Verify.expect(live ~= nil):toBe(true)
				Verify.expect(live.Size):toBe(UDim2.fromScale(1, 1))
				world.find("C").AbsoluteSize = world.V2(320, 260)
				Verify.expect(artwork.Size):toBe(UDim2.new(1, 0, 0, 180))
				local press = { UserInputType = "MouseButton1" }
				world.find("Body").Activated:Fire(press)
				world.find("Body").Activated:Fire()
				Verify.expect(inputs[1]):toBe(press)
				Verify.expect(inputs[2]):toBe("none")
				Verify.expect((world.find("C"):GetAttribute("FacetBody"))):toBe("button")
				world.stop()
				Verify.expect(released):toBe(1)
			end,
		})

		verifyHarness:case("gives an informational body no activation target and keeps its actions at rest", {
			id = "native_card::native Card::gives an informational body no activation target and keeps its actions at rest",
			run = function()
				local log: { string } = {}
				local spec = cardSpec(log)
				spec.onActivate = nil
				local world, root = mount(spec)
				Verify.expect((attr(root, "Body"))):toBe("informational")
				Verify.expect((world.find("Body"):IsA("GuiButton"))):toBe(false)
				Verify.expect(world.find("Title").Text):toBe("Nebula Racers")
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				Verify.expect(plate(world).Interactable):toBe(true)
				world.gui.SelectedObject = primary(world)
				world.action("Activate").Pressed:Fire()
				Verify.expect((table.concat(log, ","))):toBe("primary")
				world.stop()
			end,
		})

		verifyHarness:case("keeps the semantics of disabled cards and busy actions", {
			id = "native_card::native Card::keeps the semantics of disabled cards and busy actions",
			run = function()
				local log: { string } = {}
				local enabled = Compose.cell(false)
				local busy = Compose.cell(true)
				local spec = cardSpec(log, { enabled = enabled })
				spec.primaryAction.busy = busy
				spec.menu = nil
				local world, _, controls = mount(spec)
				world.find("Body").Activated:Fire()
				Verify.expect(#log):toBe(0)
				Verify.expect((assert(controls.enterActions)())):toBe(false)
				enabled:set(true)
				Verify.expect((assert(controls.enterActions)())):toBe(false)
				busy:set(false)
				Verify.expect((assert(controls.enterActions)())):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(primary(world))
				world.stop()
			end,
		})

		verifyHarness:case("keeps the last legal paint for an invalid late title or image and recovers", {
			id = "native_card::native Card::keeps the last legal paint for an invalid late title or image and recovers",
			run = function()
				local title = Compose.cell("First")
				local image = Compose.cell("rbxassetid://1")
				local world, _, controls = mount(cardSpec({}, { title = title, image = image }))
				title:set("")
				image:set("")
				Verify.expect(world.find("Title").Text):toBe("First")
				Verify.expect(world.find("Artwork").Image):toBe("rbxassetid://1")
				Verify.expect(#assert(controls.diagnostics)()):toBe(2)
				title:set("Second")
				image:set("rbxassetid://2")
				Verify.expect(world.find("Title").Text):toBe("Second")
				Verify.expect(world.find("Artwork").Image):toBe("rbxassetid://2")
				for index = 1, 20 do
					title:set("")
					title:set(`T{index}`)
				end
				Verify.expect(#assert(controls.diagnostics)()):toBe(16)
				world.stop()
			end,
		})

		verifyHarness:case("leaves nothing behind when a callback removes its own card", {
			id = "native_card::native Card::leaves nothing behind when a callback removes its own card",
			run = function()
				local show = Compose.cell(true)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "Row",
						Compose.show(show, function()
							return UI.Card("C")(cardSpec({}, {
								onActivate = function()
									show:set(false)
								end,
							}))
						end) :: unknown,
						UI.Button({ Name = "Next", label = "Next" }),
					})
				end)
				local body = world.find("Body")
				world.gui.SelectedObject = body
				body.Activated:Fire()
				Verify.expect((world.find("C"))):toBeNil()
				Verify.expect((world.find("CardCancel"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("reveals on a pointer within and keeps the action plate in the card's layout", {
			id = "native_card::native Card::reveals on a pointer within and keeps the action plate in the card's layout",
			run = function()
				local world, root = mount(cardSpec({}))
				local reveal = plate(world)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				Verify.expect(reveal.Visible):toBe(true)
				Verify.expect(reveal.Interactable):toBe(false)
				Verify.expect((fadeKit.of(reveal))):toBe(1)
				Verify.expect(reveal.LayoutOrder > world.find("Body").LayoutOrder):toBe(true)
				Verify.expect(reveal.Parent):toBe(root)
				local size = root.Size
				hover(root, true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				Verify.expect(reveal.Interactable):toBe(true)
				Verify.expect((fadeKit.of(reveal))):toBe(0)
				Verify.expect(root.Size):toBe(size)
				Verify.expect(reveal.Visible):toBe(true)
				hover(root, false)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("measures the envelope height at rest, before anything reveals", {
			id = "native_card::native Card::measures the envelope height at rest, before anything reveals",
			run = function()
				local world, root, controls = mount(cardSpec({}))
				world.resize(root, 240, 312)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				Verify.expect(controls.revealExtent:peek().body):toBe(312)
				world.stop()
			end,
		})

		verifyHarness:case("keeps hidden actions out of reach at rest and lets a selected body reveal them", {
			id = "native_card::native Card::keeps hidden actions out of reach at rest and lets a selected body reveal them",
			run = function()
				local log: { string } = {}
				local world, root = mount(cardSpec(log))
				primary(world).Activated:Fire()
				Verify.expect(#log):toBe(0)
				Verify.expect(plate(world).Interactable):toBe(false)
				world.gui.SelectedObject = world.find("Body")
				Verify.expect((attr(root, "FocusWithin"))):toBe(true)
				Verify.expect(plate(world).Interactable):toBe(true)
				primary(world).Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("primary")
				world.stop()
			end,
		})

		verifyHarness:case("reveals on focus within, keeps it when the pointer leaves and ends it when focus leaves", {
			id = "native_card::native Card::reveals on focus within, keeps it when the pointer leaves and ends it when focus leaves",
			run = function()
				local world, root = mount(cardSpec({}))
				hover(root, true)
				world.gui.SelectedObject = world.find("Body")
				hover(root, false)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.gui.SelectedObject = primary(world)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.gui.SelectedObject = world.find("Next")
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("holds the reveal while its menu is open and releases it when the menu closes", {
			id = "native_card::native Card::holds the reveal while its menu is open and releases it when the menu closes",
			run = function()
				local world, root = mount(cardSpec({}))
				hover(root, true)
				more(world).Activated:Fire()
				hover(root, false)
				Verify.expect((attr(root, "MenuOpen"))):toBe(true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.action("ModalBack").Pressed:Fire()
				Verify.expect((attr(root, "MenuOpen"))):toBe(false)
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the reveal while a press is held on an action after the pointer leaves", {
			id = "native_card::native Card::keeps the reveal while a press is held on an action after the pointer leaves",
			run = function()
				local world, root = mount(cardSpec({}))
				hover(root, true)
				primary(world).GuiState = world.engine.types.Enum.GuiState.Press
				hover(root, false)
				Verify.expect((attr(root, "Pressing"))):toBe(true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				primary(world).GuiState = world.engine.types.Enum.GuiState.Idle
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
				local held, heldRoot = mount(cardSpec({}))
				local Enum = held.engine.types.Enum
				local button = primary(held)
				hover(heldRoot, true)
				button.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
				button.GuiState = Enum.GuiState.Press
				hover(heldRoot, false)
				button.GuiState = Enum.GuiState.Idle
				Verify.expect((attr(heldRoot, "Revealed"))):toBe(true)
				button.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
				Verify.expect((attr(heldRoot, "Revealed"))):toBe(false)
				held.stop()
			end,
		})

		verifyHarness:case("keeps the actions at rest while touch is present and runs the body on the first tap", {
			id = "native_card::native Card::keeps the actions at rest while touch is present and runs the body on the first tap",
			run = function()
				local log: { string } = {}
				local world, root = mount(cardSpec(log), nil, true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.find("Body").Activated:Fire()
				Verify.expect((table.concat(log, ","))):toBe("body")
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.input.TouchEnabled = false
				Verify.expect((attr(root, "Revealed"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("takes no tap on hidden actions and never fires a press cut off by disabling", {
			id = "native_card::native Card::takes no tap on hidden actions and never fires a press cut off by disabling",
			run = function()
				local log: { string } = {}
				local enabled = Compose.cell(true)
				local world, root = mount(cardSpec(log, { enabled = enabled }))
				primary(world).Activated:Fire()
				Verify.expect(#log):toBe(0)
				hover(root, true)
				primary(world).GuiState = world.engine.types.Enum.GuiState.Press
				enabled:set(false)
				primary(world).GuiState = world.engine.types.Enum.GuiState.Idle
				primary(world).Activated:Fire()
				Verify.expect(#log):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("retargets the fade from where it is on a rapid reversal", {
			id = "native_card::native Card::retargets the fade from where it is on a rapid reversal",
			run = function()
				local world, root = mount(cardSpec({}), { motionLevel = "normal" })
				local reveal = plate(world)
				local function alpha(): number
					return 1 - fadeKit.of(reveal)
				end
				hover(root, true)
				settle(world, 0.08)
				local reached = alpha()
				Verify.expect(reached > 0.2 and reached < 1):toBe(true)
				hover(root, false)
				Verify.expect(reveal.Interactable):toBe(false)
				settle(world, 1 / 60)
				local turned = alpha()
				Verify.expect(turned < reached and turned > reached - 0.2):toBe(true)
				hover(root, true)
				settle(world, 1 / 60)
				Verify.expect(math.abs(alpha() - turned) < 0.2):toBe(true)
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("reveals the action row at rest with reveal always", {
			id = "native_card::native Card::reveals the action row at rest with reveal always",
			run = function()
				local world, root = mount(cardSpec({}, { reveal = "always" }))
				Verify.expect((attr(root, "Revealed"))):toBe(true)
				Verify.expect((fadeKit.of(plate(world)))):toBe(0)
				Verify.expect(primary(world) ~= nil):toBe(true)
				Verify.expect(plate(world).LayoutOrder):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("grows the card's one plate down around Play and More instead of stacking a second one", {
			id = "native_card::native Card::grows the card's one plate down around Play and More instead of stacking a second one",
			run = function()
				local world, root = mount(cardSpec({}))
				local E = world.engine.types.Enum
				local radius = Facet.themes.neutralPackage().metrics.radii.panel
				Verify.expect(root:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(-2 * radius)
				local reveal = plate(world)
				local paint = reveal:FindFirstChild("Plate", true)
				Verify.expect(paint ~= nil and paint:HasTag("facet-panel")):toBe(true)
				Verify.expect(`{paint.Size} {paint.Position}`):toBe(`{UDim2.fromScale(1, 1)} {UDim2.new()}`)
				Verify.expect(reveal.ZIndex < world.find("Body").ZIndex):toBe(true)
				Verify.expect((paint:FindFirstChildWhichIsA("UICorner"))):toBe(nil)
				local row = reveal:FindFirstChild("Row", true)
				Verify.expect(row.ZIndex > paint.ZIndex):toBe(true)
				Verify.expect(row:FindFirstChildWhichIsA("UIPadding") ~= nil):toBe(true)
				local play, trigger = primary(world), more(world)
				Verify.expect(play.Parent):toBe(row)
				Verify.expect(play:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(E.UIFlexMode.Fill)
				Verify.expect(trigger.Parent):toBe(row)
				Verify.expect(trigger.LayoutOrder > play.LayoutOrder):toBe(true)
				Verify.expect((trigger:GetAttribute("label"))):toBe("More")
				Verify.expect(trigger:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				Verify.expect((trigger:FindFirstChild("Title", true))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("keeps an always row unplated below the body with a gap", {
			id = "native_card::native Card::keeps an always row unplated below the body with a gap",
			run = function()
				local world, root = mount(cardSpec({}, { reveal = "always" }))
				Verify.expect(root:FindFirstChildWhichIsA("UIListLayout").Padding.Offset > 0):toBe(true)
				Verify.expect(plate(world):FindFirstChild("Plate").Visible):toBe(false)
				Verify.expect((plate(world):FindFirstChild("Row"):FindFirstChildWhichIsA("UIPadding"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("follows a live change of the measured envelope while revealed", {
			id = "native_card::native Card::follows a live change of the measured envelope while revealed",
			run = function()
				local world, root, controls = mount(cardSpec({}, { Size = UDim2.fromOffset(240, 0) }))
				hover(root, true)
				world.resize(root, 240, 300)
				local before = controls.revealExtent:peek().body
				world.resize(root, 240, 340)
				Verify.expect(controls.revealExtent:peek().body > before):toBe(true)
				Verify.expect(controls.revealExtent:peek().body):toBe(340)
				Verify.expect(root.Size.X.Offset):toBe(240)
				world.stop()
			end,
		})

		verifyHarness:case("grows a lifted card evenly around its centre", {
			id = "native_card::native Card::grows a lifted card evenly around its centre",
			run = function()
				local world, root = mount(cardSpec({}), { motionLevel = "normal" })
				root.AbsoluteSize = world.engine.types.Vector2.new(300, 200)
				Verify.expect(root.Position):toBe(world.engine.types.UDim2.fromOffset(0, 0))
				hover(root, true)
				settle(world, 1)
				root.AbsoluteSize = world.engine.types.Vector2.new(312, 208)
				Verify.expect(root.Position):toBe(world.engine.types.UDim2.fromOffset(0, 0))
				Verify.expect(root.AnchorPoint.X * root.AbsoluteSize.X):toBeCloseTo(6, 0.00001)
				Verify.expect(root.AnchorPoint.Y * root.AbsoluteSize.Y):toBeCloseTo(4, 0.00001)
				world.stop()
				local position = UDim2.fromOffset(30, 40)
				local explicit, positioned = mount(
					cardSpec({}, {
						Position = position,
						AnchorPoint = world.V2(0.5, 0.5),
					}),
					{ motionLevel = "normal" }
				)
				hover(positioned, true)
				settle(explicit, 1)
				Verify.expect(positioned.Position):toBe(position)
				Verify.expect(positioned.AnchorPoint):toBe(explicit.V2(0.5, 0.5))
				explicit.stop()
				local plain = cardSpec({})
				plain.primaryAction = nil
				plain.menu = nil
				local empty, emptyRoot = mount(plain, { motionLevel = "normal" })
				Verify.expect(empty.find("Plate").Visible):toBe(false)
				hover(emptyRoot, true)
				settle(empty, 1)
				Verify.expect(empty.find("Plate").Visible):toBe(false)
				empty.stop()
			end,
		})

		verifyHarness:case(
			"lifts the card with a raised shadow for hover, selection and a held press and lands it after",
			{
				id = "native_card::native Card::lifts the card with a raised shadow for hover, selection and a held press and lands it after",
				run = function()
					local world, root = mount(cardSpec({}), { motionLevel = "normal" })
					Verify.expect((lift(root))):toBe("scale 1 shadow false")
					hover(root, true)
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
					hover(root, false)
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1 shadow false")
					world.gui.SelectedObject = world.find("Body")
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
					world.gui.SelectedObject = nil
					settle(world, 1)
					local body = world.find("Body")
					body.InputBegan:Fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
					body.InputEnded:Fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
					settle(world, 1)
					Verify.expect((lift(root))):toBe("scale 1 shadow false")
					world.stop()
				end,
			}
		)

		verifyHarness:case("does not lift for touch presses or its menu, and lifts again for gamepad selection", {
			id = "native_card::native Card::does not lift for touch presses or its menu, and lifts again for gamepad selection",
			run = function()
				local world, root, controls = mount(cardSpec({}), { motionLevel = "normal" }, true)
				local Enum = world.engine.types.Enum
				world.input.PreferredInput = Enum.PreferredInput.Touch
				local body = world.find("Body")
				body.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch })
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				body.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch })
				hover(root, true)
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				primary(world).GuiState = Enum.GuiState.Press
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				primary(world).GuiState = Enum.GuiState.Idle
				more(world).GuiState = Enum.GuiState.Press
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow false")
				Verify.expect((controls.engaged:peek())):toBe(true)
				Verify.expect((controls.revealed:peek())):toBe(true)
				more(world).GuiState = Enum.GuiState.Idle
				hover(root, false)
				world.input.PreferredInput = Enum.PreferredInput.Gamepad
				world.gui.SelectedObject = body
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1.04 shadow true")
				world.stop()
			end,
		})

		verifyHarness:case("sizes its artwork from the unlifted width, so the lift never changes the layout", {
			id = "native_card::native Card::sizes its artwork from the unlifted width, so the lift never changes the layout",
			run = function()
				local world, root = mount(cardSpec({}), { motionLevel = "normal" })
				world.resize(root, 300, 262)
				local artwork = world.find("Artwork")
				local resting = artwork.Size
				hover(root, true)
				settle(world, 1)
				Verify.expect(root:FindFirstChild("Lift").Scale):toBe(1.04)
				world.resize(root, 312, 272)
				Verify.expect(artwork.Size):toBe(resting)
				local unit = root:FindFirstChild("LayoutUnit")
				world.runtime.reactor:batch(function()
					world.resize(unit, 1.3, 1.3)
					world.resize(root, 390, 340.6)
				end)
				Verify.expect(artwork.Size):toBe(resting)
				world.stop()
			end,
		})

		verifyHarness:case("lifts a card with no body action without a shadow", {
			id = "native_card::native Card::lifts a card with no body action without a shadow",
			run = function()
				local spec = cardSpec({})
				spec.onActivate = nil
				local world, root = mount(spec, { motionLevel = "normal" })
				hover(root, true)
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1.04 shadow false")
				world.stop()
			end,
		})

		verifyHarness:case("keeps only the raised shadow under reduced motion", {
			id = "native_card::native Card::keeps only the raised shadow under reduced motion",
			run = function()
				local world, root = mount(cardSpec({}), { motionLevel = "none" })
				hover(root, true)
				settle(world, 1)
				Verify.expect((lift(root))):toBe("scale 1 shadow true")
				world.stop()
			end,
		})

		verifyHarness:case("puts the card lift on its grid browse stop so the selection ring marks the lifted card", {
			id = "native_card::native Card::puts the card lift on its grid browse stop so the selection ring marks the lifted card",
			run = function()
				local g = gridWorld(12, false, false)
				local hit = g.hit("i1")
				g.world.gui.SelectedObject = hit
				settle(g.world, 1)
				Verify.expect(hit:FindFirstChild("CardLift").Scale):toBe(1.04)
				g.world.stop()
			end,
		})

		verifyHarness:case("reveals only the card whose grid browse stop is selected and moves with the selection", {
			id = "native_card::native Card::reveals only the card whose grid browse stop is selected and moves with the selection",
			run = function()
				local g = gridWorld(12)
				g.world.gui.SelectedObject = g.hit("i1")
				Verify.expect((attr(g.card("i1"), "Browsing"))):toBe(true)
				Verify.expect((attr(g.card("i1"), "Revealed"))):toBe(true)
				Verify.expect((attr(g.card("i2"), "Revealed"))):toBe(false)
				Verify.expect(g.card("i1"):FindFirstChild("Reveal").Parent):toBe(g.card("i1"))
				g.world.gui.SelectedObject = g.hit("i2")
				Verify.expect((attr(g.card("i1"), "Revealed"))):toBe(false)
				Verify.expect((attr(g.card("i2"), "Revealed"))):toBe(true)
				g.world.stop()
			end,
		})

		verifyHarness:case(
			"enters the actions at the first action, traps the selection and restores the stop on Cancel",
			{
				id = "native_card::native Card::enters the actions at the first action, traps the selection and restores the stop on Cancel",
				run = function()
					local g = gridWorld(12)
					local card = g.card("i2")
					g.world.gui.SelectedObject = g.hit("i2")
					g.hit("i2").Activated:Fire()
					Verify.expect(g.world.gui.SelectedObject):toBe(card:FindFirstChild("Primary", true))
					Verify.expect((attr(card, "Entered"))):toBe(true)
					Verify.expect(#g.log):toBe(0)
					local row = card:FindFirstChild("Row", true)
					Verify.expect(row.SelectionGroup):toBe(true)
					for _, side in { "Up", "Down", "Left", "Right" } do
						Verify.expect(row["SelectionBehavior" .. side].Name):toBe("Stop")
					end
					local trigger = card:FindFirstChild("More", true)
					g.world.gui.SelectedObject = trigger
					trigger.Activated:Fire()
					Verify.expect((attr(card, "MenuOpen"))):toBe(true)
					Verify.expect((g.world.action("CardCancel"))):toBeNil()
					g.world.action("ModalBack").Pressed:Fire()
					Verify.expect((attr(card, "MenuOpen"))):toBe(false)
					g.world.gui.SelectedObject = trigger
					g.world.action("CardCancel").Pressed:Fire()
					Verify.expect(g.world.gui.SelectedObject):toBe(g.hit("i2"))
					Verify.expect((attr(card, "Entered"))):toBe(false)
					Verify.expect(row.SelectionBehaviorRight.Name):toBe("Escape")
					Verify.expect((attr(card, "Revealed"))):toBe(true)
					Verify.expect(#g.log):toBe(0)
					g.world.stop()
				end,
			}
		)

		verifyHarness:case("leaves no trap, menu or controls behind when an entered card is removed or replaced", {
			id = "native_card::native Card::leaves no trap, menu or controls behind when an entered card is removed or replaced",
			run = function()
				local g = gridWorld(12)
				g.world.gui.SelectedObject = g.hit("i1")
				g.hit("i1").Activated:Fire()
				local trigger = g.card("i1"):FindFirstChild("More", true)
				g.world.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				Verify.expect((attr(g.card("i1"), "MenuOpen"))):toBe(true)
				local rest = table.clone(g.sources.A:peek())
				table.remove(rest, 1)
				g.sources.A:set(rest)
				Verify.expect(g.controls.A.i1):toBeNil()
				Verify.expect((g.world.action("CardCancel"))):toBeNil()
				local selected = g.world.gui.SelectedObject
				Verify.expect(selected == nil or not selected:isDestroyed()):toBe(true)
				local again = table.clone(rest)
				table.insert(again, 1, { id = "i1", title = "Back" })
				g.sources.A:set(again)
				Verify.expect((attr(g.card("i1"), "Entered"))):toBe(false)
				Verify.expect((attr(g.card("i1"), "MenuOpen"))):toBe(false)
				g.world.stop()
			end,
		})

		verifyHarness:case("recycles an entered card scrolled out of the window without stranding its trap", {
			id = "native_card::native Card::recycles an entered card scrolled out of the window without stranding its trap",
			run = function()
				local g = gridWorld(60)
				g.world.gui.SelectedObject = g.hit("i1")
				g.hit("i1").Activated:Fire()
				Verify.expect((attr(g.card("i1"), "Entered"))):toBe(true)
				g.world.find("A").CanvasPosition = g.world.V2(0, 4000)
				Verify.expect(g.controls.A.i1):toBeNil()
				local selected = g.world.gui.SelectedObject
				Verify.expect(selected == nil or not selected:isDestroyed()):toBe(true)
				g.world.stop()
			end,
		})

		verifyHarness:case("keeps separate cards and entries in two grids with identical keys", {
			id = "native_card::native Card::keeps separate cards and entries in two grids with identical keys",
			run = function()
				local g = gridWorld(6, true)
				g.world.gui.SelectedObject = g.hit("i1", "B")
				g.hit("i1", "B").Activated:Fire()
				Verify.expect(g.world.gui.SelectedObject):toBe(g.card("i1", "B"):FindFirstChild("Primary", true))
				Verify.expect((attr(g.card("i1", "B"), "Entered"))):toBe(true)
				Verify.expect((attr(g.card("i1", "A"), "Entered"))):toBe(false)
				Verify.expect((attr(g.card("i1", "A"), "Revealed"))):toBe(false)
				g.world.stop()
			end,
		})

		verifyHarness:case("keeps a half gutter at the outer edges of a grid so a lifted corner card is not clipped", {
			id = "native_card::native Card::keeps a half gutter at the outer edges of a grid so a lifted corner card is not clipped",
			run = function()
				local scenario = require("../examples/gallery/scenarios/cards") :: any
				local built: any
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
					built = scenario.build({
						UI = UI,
						Compose = Compose,
						Host = Host,
						types = engine.types,
						viewport = Compose.cell({ width = 1280, height = 720 }),
					})
					return built.screen()
				end, { motionLevel = "none" })
				local grid = world.find("Games")
				grid.AbsoluteWindowSize = world.V2(1248, 640)
				local columns, crossGap, gap =
					4, math.max(16, math.ceil(312 * 1.04) - 312), math.max(16, math.ceil(320 * 1.04) - 320)
				local padding = grid:FindFirstChild("Items"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft.Offset):toBe(math.ceil(crossGap / 2))
				Verify.expect(padding.PaddingRight.Offset):toBe(math.ceil(crossGap / 2))
				Verify.expect(padding.PaddingTop.Offset):toBe(math.ceil(gap / 2))
				local first = grid:FindFirstChild("Items"):FindFirstChild("g1")
				local width = first.Size.X.Offset
				Verify.expect(width):toBe((1248 - 2 * math.ceil(crossGap / 2) - crossGap * (columns - 1)) / columns)
				local grown = width * 1.04 - width
				Verify.expect(padding.PaddingLeft.Offset >= grown / 2):toBe(true)
				Verify.expect(crossGap >= grown):toBe(true)
				Verify.expect(padding.PaddingTop.Offset >= (320 * 1.04 - 320) / 2):toBe(true)
				local hit = first:FindFirstChild("RowHit", true)
				Verify.expect(hit.AnchorPoint):toBe(world.V2(0.5, 0.5))
				Verify.expect(hit.Position.X.Scale):toBe(0.5)
				Verify.expect(hit.Position.Y.Scale):toBe(0.5)
				Verify.expect((built.steps.enter("g1"))):toBe(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Primary")
				world.action("Activate").Pressed:Fire()
				Verify.expect(built.report().last):toBe("Last action: play g1")
				local extent = grid.CanvasSize.Y.Offset
				Verify.expect(extent):toBe(15 * 320 + 14 * gap + 2 * math.ceil(gap / 2))
				grid.CanvasPosition = world.V2(0, 100000)
				Verify.expect(grid.CanvasPosition.Y):toBe(extent - 640)
				grid.CanvasPosition = world.V2(0, 0)
				Verify.expect(grid.CanvasPosition.Y):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("centres a count seal on the top-right corner of its host without changing the host", {
			id = "native_card::native Card::centres a count seal on the top-right corner of its host without changing the host",
			run = function()
				local unread = Compose.cell(120 :: any)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						UI.badged(UI.Button({ Name = "Inbox", label = "Inbox", LayoutOrder = 3 }), unread),
					})
				end)
				local wrapper = world.find("Inbox+badge")
				local host = world.find("Inbox")
				Verify.expect(host.Parent):toBe(wrapper)
				Verify.expect(wrapper.LayoutOrder):toBe(3)
				Verify.expect(wrapper.AutomaticSize.Name):toBe("XY")
				local corner = world.find("Corner", wrapper)
				Verify.expect(corner.Size):toBe(UDim2.fromOffset(0, 0))
				Verify.expect(corner.Position):toBe(UDim2.fromScale(1, 0))
				local seal = world.find("CornerBadge", wrapper)
				Verify.expect(seal.AnchorPoint):toBe(require("@lune/roblox").Vector2.new(0.5, 0.5))
				Verify.expect(seal.Text):toBe("99+")
				Verify.expect((seal:IsA("GuiButton"))):toBe(false)
				Verify.expect(seal.ZIndex > host.ZIndex):toBe(true)
				unread:set(7)
				Verify.expect(world.find("CornerBadge", wrapper).Text):toBe("7")
				for _, empty in { nil, false, 0, "" } :: { any } do
					unread:set(empty)
					Verify.expect((world.find("CornerBadge", wrapper))):toBeNil()
				end
				world.stop()
			end,
		})

		verifyHarness:case("mirrors the seal to the top-left in rtl and shows true as a dot", {
			id = "native_card::native Card::mirrors the seal to the top-left in rtl and shows true as a dot",
			run = function()
				local world = worlds.new(function(UI: FacetControls)
					return UI.badged(UI.Button({ Name = "Inbox", label = "Inbox" }), true, "rtl")
				end)
				local wrapper = world.find("Inbox+badge")
				Verify.expect(world.find("Corner", wrapper).Position):toBe(UDim2.fromScale(0, 0))
				Verify.expect(world.find("CornerBadge", wrapper).Text):toBe("•")
				world.stop()
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.badged(UI.Button({ label = "Inbox" }), 1, "up" :: any)
				end) ~= nil):toBe(true)
				Verify.expect(worlds.mountError(function(UI: FacetControls)
					return UI.badged(UI.Button({ label = "Inbox" }), 1.5)
				end) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("puts an icon tab count on the icon corner and a text tab count in a trailing pill", {
			id = "native_card::native Card::puts an icon tab count on the icon corner and a text tab count in a trailing pill",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("inbox"),
						placement = "topBar" :: "topBar",
						tabs = {
							{
								id = "inbox",
								label = "Inbox",
								icon = "menu",
								badge = 3,
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "sent",
								label = "Sent",
								badge = 2,
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local tabs = world.find("Tabs")
				local inbox = world.find("inbox", tabs)
				local seal = inbox:FindFirstChild("CornerBadge", true)
				Verify.expect(seal ~= nil and seal.Text == "3"):toBe(true)
				Verify.expect(seal:FindFirstAncestorWhichIsA("ImageLabel") ~= nil):toBe(true)
				local sent = world.find("sent", tabs)
				Verify.expect((sent:FindFirstChild("CornerBadge", true))):toBeNil()
				Verify.expect(sent:FindFirstChild("Count", true).Text):toBe("2")
				Verify.expect((sent:GetAttribute("label"))):toBe("Sent (2)")
				world.stop()
				local pickers = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker("Icons")({
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Inbox", icon = "menu", badge = 3 } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Sent", icon = "flag" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}) :: unknown,
						UI.Picker("Words")({
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Inbox", badge = 3 } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Sent" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end)
				local icons = pickers.find("Icons")
				local iconSeal = pickers.find("a", icons):FindFirstChild("CornerBadge", true)
				Verify.expect(iconSeal ~= nil and iconSeal.Text == "3"):toBe(true)
				Verify.expect(iconSeal:FindFirstAncestorWhichIsA("ImageLabel") ~= nil):toBe(true)
				local shown = {}
				for _, node in pickers.find("a", icons):GetDescendants() do
					if
						(node:IsA("TextLabel") or node:IsA("TextButton"))
						and node.Name ~= "CornerBadge"
						and node.Text ~= ""
					then
						table.insert(shown, node.Text)
					end
				end
				Verify.expect((table.concat(shown, ","))):toBe("Inbox")
				Verify.expect((pickers.find("b", icons):FindFirstChild("CornerBadge", true))):toBeNil()
				local words = pickers.find("a", pickers.find("Words"))
				Verify.expect((words:FindFirstChild("CornerBadge", true))):toBeNil()
				Verify.expect(words:FindFirstChild("Count", true).Text):toBe("3")
				Verify.expect((words:GetAttribute("label"))):toBe("Inbox (3)")
				pickers.stop()
			end,
		})

		verifyHarness:case("keeps the mounted cards and their controls bounded across a thousand items", {
			id = "native_card::native Card::keeps the mounted cards and their controls bounded across a thousand items",
			run = function()
				local g = gridWorld(1000)
				local function count(): number
					local n = 0
					for _ in g.cards.A do
						n += 1
					end
					return n
				end
				local bound = 7 * 3
				Verify.expect(count() > 0 and count() <= bound):toBe(true)
				local peak = 0
				for step = 1, 10 do
					g.world.find("A").CanvasPosition = g.world.V2(0, step * 2000)
					peak = math.max(peak, count())
				end
				Verify.expect(peak <= bound):toBe(true)
				Verify.expect(g.controls.A.i1):toBeNil()
				Verify.expect(g.controls.A.i500):toBeNil()
				g.world.stop()
			end,
		})
	end)

	return nil
end
