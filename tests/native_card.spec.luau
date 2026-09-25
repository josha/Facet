--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local Compose = Facet.Compose
local UDim2 = require("@lune/roblox").UDim2

local function cardSpec(log: { string }, extra: { [string]: any }?): { [string]: any }
	local spec: { [string]: any } = {
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
	for key, value in extra or {} do
		spec[key] = value
	end
	return spec
end

local function mount(
	spec: { [string]: any },
	options: { [string]: any }?,
	touch: boolean?
): (any, any, { [string]: any })
	local controls: { [string]: any } = {}
	spec.controls = controls
	local world = worlds.new(function(UI, Host)
		return Host.Frame({
			Name = "Row",
			UI.Card("C")(spec),
			UI.Button({ Name = "Next", label = "Next" }),
		})
	end, options or { reducedMotion = true })
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
	return world.find("More"):FindFirstChild("Trigger")
end

local function hover(root: any, inside: boolean)
	root:_fireSignal(if inside then "MouseEnter" else "MouseLeave")
end

local function settle(world: any, seconds: number)
	for _ = 1, math.ceil(seconds * 60) do
		world.engine.heartbeat.fire(1 / 60)
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
	local world = worlds.new(function(UI, Host)
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
				render = function(current: any, _placement: any, key: string)
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
		return Host.Frame({ Name = "Page", table.unpack(children) })
	end, { reducedMotion = reduced ~= false })
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

t.describe("native Card", function()
	t.it("refuses malformed specs before building anything", function()
		local bad: { any } = {
			{ image = "", title = "T" },
			{ image = "rbxassetid://1" },
			{ image = "rbxassetid://1", title = "T", reveal = "hover" },
			{ image = "rbxassetid://1", title = "T", imageAspectRatio = 0 },
			{ image = "rbxassetid://1", title = "T", primaryAction = { label = "Play" } },
			{ image = "rbxassetid://1", title = "T", primaryAction = { label = "P", onActivate = print, x = 1 } },
			{ image = "rbxassetid://1", title = "T", menu = { items = {}, extra = true } },
			{ image = "rbxassetid://1", title = "T", caption = 5 },
			{ image = "rbxassetid://1", title = "T", zIndex = 3 },
			{ title = "T" },
			{ title = "T", artwork = "rbxassetid://1" },
			{ image = "", title = "T", artwork = function() end },
		}
		for _, spec in bad do
			t.expect(worlds.mountError(function(UI)
				return UI.Card(spec)
			end) ~= nil).toBe(true)
		end
	end)

	t.it("keeps body, primary and More as sibling targets so one press runs one intent", function()
		local log: { string } = {}
		local world, root = mount(cardSpec(log))
		t.expect(world.find("Body").Parent).toBe(root)
		t.expect(primary(world).Parent.Parent.Parent).toBe(root)
		t.expect(root:IsA("GuiButton")).toBe(false)
		world.find("Body").Activated.fire()
		t.expect(table.concat(log, ",")).toBe("body")
		hover(root, true)
		primary(world).Activated.fire()
		t.expect(table.concat(log, ",")).toBe("body,primary")
		more(world).Activated.fire()
		t.expect(attr(root, "MenuOpen")).toBe(true)
		t.expect(table.concat(log, ",")).toBe("body,primary")
		world.stop()
	end)

	t.it("draws live artwork in the artwork frame and forwards the activating input to the body", function()
		local inputs: { any } = {}
		local released = 0
		local world = worlds.new(function(UI, Host)
			return UI.Card "C" {
				title = "Afterlight",
				artwork = function()
					Compose.cleanup(function()
						released += 1
					end)
					return Host.ViewportFrame({ Name = "Preview" })
				end,
				onActivate = function(input)
					table.insert(inputs, input or "none")
				end,
			}
		end, { reducedMotion = true })
		local artwork = world.find("Artwork")
		local live = artwork:FindFirstChild("Preview")
		t.expect(artwork.Image).toBe("")
		t.expect(live ~= nil).toBe(true)
		t.expect(live.Size).toBe(UDim2.fromScale(1, 1))
		world.find("C").AbsoluteSize = world.V2(320, 260)
		t.expect(artwork.Size).toBe(UDim2.new(1, 0, 0, 180))
		local press = { UserInputType = "MouseButton1" }
		world.find("Body").Activated.fire(press)
		world.find("Body").Activated.fire()
		t.expect(inputs[1]).toBe(press)
		t.expect(inputs[2]).toBe("none")
		t.expect(world.find("C"):GetAttribute("FacetBody")).toBe("button")
		world.stop()
		t.expect(released).toBe(1)
	end)

	t.it("gives an informational body no activation target and keeps its actions at rest", function()
		local log: { string } = {}
		local spec = cardSpec(log)
		spec.onActivate = nil
		local world, root = mount(spec)
		t.expect(attr(root, "Body")).toBe("informational")
		t.expect(world.find("Body"):IsA("GuiButton")).toBe(false)
		t.expect(world.find("Title").Text).toBe("Nebula Racers")
		t.expect(attr(root, "Revealed")).toBe(true)
		t.expect(plate(world).Interactable).toBe(true)
		world.gui.SelectedObject = primary(world)
		world.action("Activate").Pressed.fire()
		t.expect(table.concat(log, ",")).toBe("primary")
		world.stop()
	end)

	t.it("keeps the semantics of disabled cards and busy actions", function()
		local log: { string } = {}
		local enabled = Compose.cell(false)
		local busy = Compose.cell(true)
		local spec = cardSpec(log, { enabled = enabled })
		spec.primaryAction.busy = busy
		spec.menu = nil
		local world, _, controls = mount(spec)
		world.find("Body").Activated.fire()
		t.expect(#log).toBe(0)
		t.expect(controls.enterActions()).toBe(false)
		enabled:set(true)
		t.expect(controls.enterActions()).toBe(false)
		busy:set(false)
		t.expect(controls.enterActions()).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(primary(world))
		world.stop()
	end)

	t.it("keeps the last legal paint for an invalid late title or image and recovers", function()
		local title = Compose.cell("First")
		local image = Compose.cell("rbxassetid://1")
		local world, _, controls = mount(cardSpec({}, { title = title, image = image }))
		title:set("")
		image:set("")
		t.expect(world.find("Title").Text).toBe("First")
		t.expect(world.find("Artwork").Image).toBe("rbxassetid://1")
		t.expect(#controls.diagnostics()).toBe(2)
		title:set("Second")
		image:set("rbxassetid://2")
		t.expect(world.find("Title").Text).toBe("Second")
		t.expect(world.find("Artwork").Image).toBe("rbxassetid://2")
		for index = 1, 20 do
			title:set("")
			title:set(`T{index}`)
		end
		t.expect(#controls.diagnostics()).toBe(16)
		world.stop()
	end)

	t.it("leaves nothing behind when a callback removes its own card", function()
		local show = Compose.cell(true)
		local world = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "Row",
				Compose.show(show, function()
					return UI.Card("C")(cardSpec({}, {
						onActivate = function()
							show:set(false)
						end,
					}))
				end),
				UI.Button({ Name = "Next", label = "Next" }),
			})
		end)
		local body = world.find("Body")
		world.gui.SelectedObject = body
		body.Activated.fire()
		t.expect(world.find("C")).toBeNil()
		t.expect(world.find("CardCancel")).toBeNil()
		world.stop()
	end)

	t.it("reveals on a pointer within and keeps the action plate in the card's layout", function()
		local world, root = mount(cardSpec({}))
		local reveal = plate(world)
		t.expect(attr(root, "Revealed")).toBe(false)
		t.expect(reveal.Visible).toBe(true)
		t.expect(reveal.Interactable).toBe(false)
		t.expect(reveal.GroupTransparency).toBe(1)
		t.expect(reveal.LayoutOrder > world.find("Body").LayoutOrder).toBe(true)
		t.expect(reveal.Parent).toBe(root)
		local size = root.Size
		hover(root, true)
		t.expect(attr(root, "Revealed")).toBe(true)
		t.expect(reveal.Interactable).toBe(true)
		t.expect(reveal.GroupTransparency).toBe(0)
		t.expect(root.Size).toBe(size)
		t.expect(reveal.Visible).toBe(true)
		hover(root, false)
		t.expect(attr(root, "Revealed")).toBe(false)
		world.stop()
	end)

	t.it("measures the envelope height at rest, before anything reveals", function()
		local world, root, controls = mount(cardSpec({}))
		world.resize(root, 240, 312)
		t.expect(attr(root, "Revealed")).toBe(false)
		t.expect(controls.revealExtent:peek().body).toBe(312)
		world.stop()
	end)

	t.it("keeps hidden actions out of reach at rest and lets a selected body reveal them", function()
		local log: { string } = {}
		local world, root = mount(cardSpec(log))
		primary(world).Activated.fire()
		t.expect(#log).toBe(0)
		t.expect(plate(world).Interactable).toBe(false)
		world.gui.SelectedObject = world.find("Body")
		t.expect(attr(root, "FocusWithin")).toBe(true)
		t.expect(plate(world).Interactable).toBe(true)
		primary(world).Activated.fire()
		t.expect(table.concat(log, ",")).toBe("primary")
		world.stop()
	end)

	t.it("reveals on focus within, keeps it when the pointer leaves and ends it when focus leaves", function()
		local world, root = mount(cardSpec({}))
		hover(root, true)
		world.gui.SelectedObject = world.find("Body")
		hover(root, false)
		t.expect(attr(root, "Revealed")).toBe(true)
		world.gui.SelectedObject = primary(world)
		t.expect(attr(root, "Revealed")).toBe(true)
		world.gui.SelectedObject = world.find("Next")
		t.expect(attr(root, "Revealed")).toBe(false)
		world.stop()
	end)

	t.it("holds the reveal while its menu is open and releases it when the menu closes", function()
		local world, root = mount(cardSpec({}))
		hover(root, true)
		more(world).Activated.fire()
		hover(root, false)
		t.expect(attr(root, "MenuOpen")).toBe(true)
		t.expect(attr(root, "Revealed")).toBe(true)
		world.action("ModalBack").Pressed.fire()
		t.expect(attr(root, "MenuOpen")).toBe(false)
		t.expect(attr(root, "Revealed")).toBe(false)
		world.stop()
	end)

	t.it("keeps the reveal while a press is held on an action after the pointer leaves", function()
		local world, root = mount(cardSpec({}))
		hover(root, true)
		primary(world).GuiState = world.engine.types.Enum.GuiState.Press
		hover(root, false)
		t.expect(attr(root, "Pressing")).toBe(true)
		t.expect(attr(root, "Revealed")).toBe(true)
		primary(world).GuiState = world.engine.types.Enum.GuiState.Idle
		t.expect(attr(root, "Revealed")).toBe(false)
		world.stop()
		local held, heldRoot = mount(cardSpec({}))
		local Enum = held.engine.types.Enum
		local button = primary(held)
		hover(heldRoot, true)
		button.InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		button.GuiState = Enum.GuiState.Press
		hover(heldRoot, false)
		button.GuiState = Enum.GuiState.Idle
		t.expect(attr(heldRoot, "Revealed")).toBe(true)
		button.InputEnded.fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		t.expect(attr(heldRoot, "Revealed")).toBe(false)
		held.stop()
	end)

	t.it("keeps the actions at rest while touch is present and runs the body on the first tap", function()
		local log: { string } = {}
		local world, root = mount(cardSpec(log), nil, true)
		t.expect(attr(root, "Revealed")).toBe(true)
		world.find("Body").Activated.fire()
		t.expect(table.concat(log, ",")).toBe("body")
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(attr(root, "Revealed")).toBe(true)
		world.input.TouchEnabled = false
		t.expect(attr(root, "Revealed")).toBe(false)
		world.stop()
	end)

	t.it("takes no tap on hidden actions and never fires a press cut off by disabling", function()
		local log: { string } = {}
		local enabled = Compose.cell(true)
		local world, root = mount(cardSpec(log, { enabled = enabled }))
		primary(world).Activated.fire()
		t.expect(#log).toBe(0)
		hover(root, true)
		primary(world).GuiState = world.engine.types.Enum.GuiState.Press
		enabled:set(false)
		primary(world).GuiState = world.engine.types.Enum.GuiState.Idle
		primary(world).Activated.fire()
		t.expect(#log).toBe(0)
		world.stop()
	end)

	t.it("retargets the fade from where it is on a rapid reversal", function()
		local world, root = mount(cardSpec({}), { reducedMotion = false })
		local reveal = plate(world)
		local function alpha(): number
			return 1 - reveal.GroupTransparency
		end
		hover(root, true)
		settle(world, 0.08)
		local reached = alpha()
		t.expect(reached > 0.2 and reached < 1).toBe(true)
		hover(root, false)
		t.expect(reveal.Interactable).toBe(false)
		settle(world, 1 / 60)
		local turned = alpha()
		t.expect(turned < reached and turned > reached - 0.2).toBe(true)
		hover(root, true)
		settle(world, 1 / 60)
		t.expect(math.abs(alpha() - turned) < 0.2).toBe(true)
		t.expect(attr(root, "Revealed")).toBe(true)
		world.stop()
	end)

	t.it("reveals the action row at rest with reveal always", function()
		local world, root = mount(cardSpec({}, { reveal = "always" }))
		t.expect(attr(root, "Revealed")).toBe(true)
		t.expect(plate(world).GroupTransparency).toBe(0)
		t.expect(primary(world) ~= nil).toBe(true)
		t.expect(plate(world).LayoutOrder).toBe(2)
		world.stop()
	end)

	t.it("follows a live change of the measured envelope while revealed", function()
		local world, root, controls = mount(cardSpec({}, { Size = UDim2.fromOffset(240, 0) }))
		hover(root, true)
		world.resize(root, 240, 300)
		local before = controls.revealExtent:peek().body
		world.resize(root, 240, 340)
		t.expect(controls.revealExtent:peek().body > before).toBe(true)
		t.expect(controls.revealExtent:peek().body).toBe(340)
		t.expect(root.Size.X.Offset).toBe(240)
		world.stop()
	end)

	t.it("grows a lifted card evenly around its centre", function()
		local world, root = mount(cardSpec({}), { reducedMotion = false })
		root.AbsoluteSize = world.engine.types.Vector2.new(300, 200)
		t.expect(root.Position).toBe(world.engine.types.UDim2.fromOffset(0, 0))
		hover(root, true)
		settle(world, 1)
		root.AbsoluteSize = world.engine.types.Vector2.new(312, 208)
		t.expect(root.Position).toBe(world.engine.types.UDim2.fromOffset(-6, -4))
		world.stop()
	end)

	t.it("lifts the card with a raised shadow for hover, selection and a held press and lands it after", function()
		local world, root = mount(cardSpec({}), { reducedMotion = false })
		t.expect(lift(root)).toBe("scale 1 shadow false")
		hover(root, true)
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1.04 shadow true")
		hover(root, false)
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow false")
		world.gui.SelectedObject = world.find("Body")
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1.04 shadow true")
		world.gui.SelectedObject = nil
		settle(world, 1)
		local body = world.find("Body")
		body.InputBegan.fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1.04 shadow true")
		body.InputEnded.fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow false")
		world.stop()
	end)

	t.it("does not lift for touch presses or its menu, and lifts again for gamepad selection", function()
		local world, root, controls = mount(cardSpec({}), { reducedMotion = false }, true)
		local Enum = world.engine.types.Enum
		world.input.PreferredInput = Enum.PreferredInput.Touch
		local body = world.find("Body")
		body.InputBegan.fire({ UserInputType = Enum.UserInputType.Touch })
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow false")
		body.InputEnded.fire({ UserInputType = Enum.UserInputType.Touch })
		hover(root, true)
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow false")
		primary(world).GuiState = Enum.GuiState.Press
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow false")
		primary(world).GuiState = Enum.GuiState.Idle
		more(world).GuiState = Enum.GuiState.Press
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow false")
		t.expect(controls.engaged:peek()).toBe(true)
		t.expect(controls.revealed:peek()).toBe(true)
		more(world).GuiState = Enum.GuiState.Idle
		hover(root, false)
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		world.gui.SelectedObject = body
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1.04 shadow true")
		world.stop()
	end)

	t.it("sizes its artwork from the unlifted width, so the lift never changes the layout", function()
		local world, root = mount(cardSpec({}), { reducedMotion = false })
		world.resize(root, 300, 262)
		local artwork = world.find("Artwork")
		local resting = artwork.Size
		hover(root, true)
		settle(world, 1)
		t.expect(root:FindFirstChild("Lift").Scale).toBe(1.04)
		world.resize(root, 312, 272)
		t.expect(artwork.Size).toBe(resting)
		world.stop()
	end)

	t.it("lifts a card with no body action without a shadow", function()
		local spec = cardSpec({})
		spec.onActivate = nil
		local world, root = mount(spec, { reducedMotion = false })
		hover(root, true)
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1.04 shadow false")
		world.stop()
	end)

	t.it("keeps only the raised shadow under reduced motion", function()
		local world, root = mount(cardSpec({}), { reducedMotion = true })
		hover(root, true)
		settle(world, 1)
		t.expect(lift(root)).toBe("scale 1 shadow true")
		world.stop()
	end)

	t.it("puts the card lift on its grid browse stop so the selection ring marks the lifted card", function()
		local g = gridWorld(12, false, false)
		local hit = g.hit("i1")
		g.world.gui.SelectedObject = hit
		settle(g.world, 1)
		t.expect(hit:FindFirstChild("CardLift").Scale).toBe(1.04)
		g.world.stop()
	end)

	t.it("reveals only the card whose grid browse stop is selected and moves with the selection", function()
		local g = gridWorld(12)
		g.world.gui.SelectedObject = g.hit("i1")
		t.expect(attr(g.card("i1"), "Browsing")).toBe(true)
		t.expect(attr(g.card("i1"), "Revealed")).toBe(true)
		t.expect(attr(g.card("i2"), "Revealed")).toBe(false)
		t.expect(g.card("i1"):FindFirstChild("Reveal").Parent).toBe(g.card("i1"))
		g.world.gui.SelectedObject = g.hit("i2")
		t.expect(attr(g.card("i1"), "Revealed")).toBe(false)
		t.expect(attr(g.card("i2"), "Revealed")).toBe(true)
		g.world.stop()
	end)

	t.it("enters the actions at the first action, traps the selection and restores the stop on Cancel", function()
		local g = gridWorld(12)
		local card = g.card("i2")
		g.world.gui.SelectedObject = g.hit("i2")
		g.hit("i2").Activated.fire()
		t.expect(g.world.gui.SelectedObject).toBe(card:FindFirstChild("Primary", true))
		t.expect(attr(card, "Entered")).toBe(true)
		t.expect(#g.log).toBe(0)
		local row = card:FindFirstChild("Row", true)
		t.expect(row.SelectionGroup).toBe(true)
		for _, side in { "Up", "Down", "Left", "Right" } do
			t.expect(row["SelectionBehavior" .. side].Name).toBe("Stop")
		end
		local trigger = card:FindFirstChild("More", true):FindFirstChild("Trigger")
		g.world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		t.expect(attr(card, "MenuOpen")).toBe(true)
		t.expect(g.world.action("CardCancel")).toBeNil()
		g.world.action("ModalBack").Pressed.fire()
		t.expect(attr(card, "MenuOpen")).toBe(false)
		g.world.gui.SelectedObject = trigger
		g.world.action("CardCancel").Pressed.fire()
		t.expect(g.world.gui.SelectedObject).toBe(g.hit("i2"))
		t.expect(attr(card, "Entered")).toBe(false)
		t.expect(row.SelectionBehaviorRight.Name).toBe("Escape")
		t.expect(attr(card, "Revealed")).toBe(true)
		t.expect(#g.log).toBe(0)
		g.world.stop()
	end)

	t.it("leaves no trap, menu or controls behind when an entered card is removed or replaced", function()
		local g = gridWorld(12)
		g.world.gui.SelectedObject = g.hit("i1")
		g.hit("i1").Activated.fire()
		local trigger = g.card("i1"):FindFirstChild("More", true):FindFirstChild("Trigger")
		g.world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		t.expect(attr(g.card("i1"), "MenuOpen")).toBe(true)
		local rest = table.clone(g.sources.A:peek())
		table.remove(rest, 1)
		g.sources.A:set(rest)
		t.expect(g.controls.A.i1).toBeNil()
		t.expect(g.world.action("CardCancel")).toBeNil()
		local selected = g.world.gui.SelectedObject
		t.expect(selected == nil or not selected:isDestroyed()).toBe(true)
		local again = table.clone(rest)
		table.insert(again, 1, { id = "i1", title = "Back" })
		g.sources.A:set(again)
		t.expect(attr(g.card("i1"), "Entered")).toBe(false)
		t.expect(attr(g.card("i1"), "MenuOpen")).toBe(false)
		g.world.stop()
	end)

	t.it("recycles an entered card scrolled out of the window without stranding its trap", function()
		local g = gridWorld(60)
		g.world.gui.SelectedObject = g.hit("i1")
		g.hit("i1").Activated.fire()
		t.expect(attr(g.card("i1"), "Entered")).toBe(true)
		g.world.find("A").CanvasPosition = g.world.V2(0, 4000)
		t.expect(g.controls.A.i1).toBeNil()
		local selected = g.world.gui.SelectedObject
		t.expect(selected == nil or not selected:isDestroyed()).toBe(true)
		g.world.stop()
	end)

	t.it("keeps separate cards and entries in two grids with identical keys", function()
		local g = gridWorld(6, true)
		g.world.gui.SelectedObject = g.hit("i1", "B")
		g.hit("i1", "B").Activated.fire()
		t.expect(g.world.gui.SelectedObject).toBe(g.card("i1", "B"):FindFirstChild("Primary", true))
		t.expect(attr(g.card("i1", "B"), "Entered")).toBe(true)
		t.expect(attr(g.card("i1", "A"), "Entered")).toBe(false)
		t.expect(attr(g.card("i1", "A"), "Revealed")).toBe(false)
		g.world.stop()
	end)

	t.it("keeps a half gutter at the outer edges of a grid so a lifted corner card is not clipped", function()
		local scenario = require("../examples/gallery/scenarios/cards") :: any
		local built: any
		local world = worlds.new(function(UI, Host, engine)
			built = scenario.build({
				UI = UI,
				Compose = Compose,
				Host = Host,
				types = engine.types,
				viewport = Compose.cell({ width = 1280, height = 720 }),
			})
			return built.screen()
		end, { reducedMotion = true })
		local grid = world.find("Games")
		grid.AbsoluteWindowSize = world.V2(1248, 640)
		local columns, crossGap, gap =
			4, math.max(16, math.ceil(312 * 1.04) - 312), math.max(16, math.ceil(320 * 1.04) - 320)
		local padding = grid:FindFirstChild("Items"):FindFirstChildWhichIsA("UIPadding")
		t.expect(padding.PaddingLeft.Offset).toBe(math.ceil(crossGap / 2))
		t.expect(padding.PaddingRight.Offset).toBe(math.ceil(crossGap / 2))
		t.expect(padding.PaddingTop.Offset).toBe(math.ceil(gap / 2))
		local first = grid:FindFirstChild("Items"):FindFirstChild("g1")
		local width = first.Size.X.Offset
		t.expect(width).toBe((1248 - 2 * math.ceil(crossGap / 2) - crossGap * (columns - 1)) / columns)
		local grown = width * 1.04 - width
		t.expect(padding.PaddingLeft.Offset >= grown / 2).toBe(true)
		t.expect(crossGap >= grown).toBe(true)
		t.expect(padding.PaddingTop.Offset >= (320 * 1.04 - 320) / 2).toBe(true)
		local hit = first:FindFirstChild("RowHit", true)
		t.expect(hit.AnchorPoint).toBe(world.V2(0.5, 0.5))
		t.expect(hit.Position.X.Scale).toBe(0.5)
		t.expect(hit.Position.Y.Scale).toBe(0.5)
		t.expect(built.steps.enter("g1")).toBe(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Primary")
		world.action("Activate").Pressed.fire()
		t.expect(built.report().last).toBe("Last action: play g1")
		local extent = grid.CanvasSize.Y.Offset
		t.expect(extent).toBe(15 * 320 + 14 * gap + 2 * math.ceil(gap / 2))
		grid.CanvasPosition = world.V2(0, 100000)
		t.expect(grid.CanvasPosition.Y).toBe(extent - 640)
		grid.CanvasPosition = world.V2(0, 0)
		t.expect(grid.CanvasPosition.Y).toBe(0)
		world.stop()
	end)

	t.it("centres a count seal on the top-right corner of its host without changing the host", function()
		local unread = Compose.cell(120 :: any)
		local world = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				UI.badged(UI.Button({ Name = "Inbox", label = "Inbox", LayoutOrder = 3 }), unread),
			})
		end)
		local wrapper = world.find("Inbox+badge")
		local host = world.find("Inbox")
		t.expect(host.Parent).toBe(wrapper)
		t.expect(wrapper.LayoutOrder).toBe(3)
		t.expect(wrapper.AutomaticSize.Name).toBe("XY")
		local corner = world.find("Corner", wrapper)
		t.expect(corner.Size).toBe(UDim2.fromOffset(0, 0))
		t.expect(corner.Position).toBe(UDim2.fromScale(1, 0))
		local seal = world.find("CornerBadge", wrapper)
		t.expect(seal.AnchorPoint).toBe(require("@lune/roblox").Vector2.new(0.5, 0.5))
		t.expect(seal.Text).toBe("99+")
		t.expect(seal:IsA("GuiButton")).toBe(false)
		t.expect(seal.ZIndex > host.ZIndex).toBe(true)
		unread:set(7)
		t.expect(world.find("CornerBadge", wrapper).Text).toBe("7")
		for _, empty in { nil, false, 0, "" } :: { any } do
			unread:set(empty)
			t.expect(world.find("CornerBadge", wrapper)).toBeNil()
		end
		world.stop()
	end)

	t.it("mirrors the seal to the top-left in rtl and shows true as a dot", function()
		local world = worlds.new(function(UI)
			return UI.badged(UI.Button({ Name = "Inbox", label = "Inbox" }), true, "rtl")
		end)
		local wrapper = world.find("Inbox+badge")
		t.expect(world.find("Corner", wrapper).Position).toBe(UDim2.fromScale(0, 0))
		t.expect(world.find("CornerBadge", wrapper).Text).toBe("•")
		world.stop()
		t.expect(worlds.mountError(function(UI)
			return UI.badged(UI.Button({ label = "Inbox" }), 1, "up" :: any)
		end) ~= nil).toBe(true)
		t.expect(worlds.mountError(function(UI)
			return UI.badged(UI.Button({ label = "Inbox" }), 1.5)
		end) ~= nil).toBe(true)
	end)

	t.it("puts an icon tab count on the icon corner and keeps a text tab count in its words", function()
		local world = worlds.new(function(UI, Host)
			return UI.TabView({
				selection = Compose.cell("inbox"),
				placement = "topBar",
				tabs = {
					{
						id = "inbox",
						label = "Inbox",
						icon = "menu",
						badge = 3,
						content = function()
							return Host.Frame({})
						end,
					},
					{
						id = "sent",
						label = "Sent",
						badge = 2,
						content = function()
							return Host.Frame({})
						end,
					},
				},
			})
		end)
		local tabs = world.find("Tabs")
		local inbox = world.find("inbox", tabs)
		local seal = inbox:FindFirstChild("CornerBadge", true)
		t.expect(seal ~= nil and seal.Text == "3").toBe(true)
		t.expect(seal:FindFirstAncestorWhichIsA("ImageLabel") ~= nil).toBe(true)
		local sent = world.find("sent", tabs)
		t.expect(sent:FindFirstChild("CornerBadge", true)).toBeNil()
		t.expect(sent.Text).toBe("Sent (2)")
		world.stop()
		local pickers = worlds.new(function(UI, Host)
			return Host.Frame({
				UI.Picker("Icons")({
					style = "segmented",
					selected = Compose.cell("a"),
					options = {
						{ value = "a", label = "Inbox", icon = "menu", badge = 3 },
						{ value = "b", label = "Sent", icon = "flag" },
					},
				}),
				UI.Picker("Words")({
					style = "segmented",
					selected = Compose.cell("a"),
					options = { { value = "a", label = "Inbox", badge = 3 }, { value = "b", label = "Sent" } },
				}),
			})
		end)
		local icons = pickers.find("Icons")
		local iconSeal = pickers.find("a", icons):FindFirstChild("CornerBadge", true)
		t.expect(iconSeal ~= nil and iconSeal.Text == "3").toBe(true)
		t.expect(iconSeal:FindFirstAncestorWhichIsA("ImageLabel") ~= nil).toBe(true)
		local shown = {}
		for _, node in pickers.find("a", icons):GetDescendants() do
			if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Name ~= "CornerBadge" and node.Text ~= "" then
				table.insert(shown, node.Text)
			end
		end
		t.expect(table.concat(shown, ",")).toBe("Inbox")
		t.expect(pickers.find("b", icons):FindFirstChild("CornerBadge", true)).toBeNil()
		local words = pickers.find("a", pickers.find("Words"))
		t.expect(words:FindFirstChild("CornerBadge", true)).toBeNil()
		t.expect(words.Text).toBe("Inbox (3)")
		pickers.stop()
	end)

	t.it("keeps the mounted cards and their controls bounded across a thousand items", function()
		local g = gridWorld(1000)
		local function count(): number
			local n = 0
			for _ in g.cards.A do
				n += 1
			end
			return n
		end
		local bound = 7 * 3
		t.expect(count() > 0 and count() <= bound).toBe(true)
		local peak = 0
		for step = 1, 10 do
			g.world.find("A").CanvasPosition = g.world.V2(0, step * 2000)
			peak = math.max(peak, count())
		end
		t.expect(peak <= bound).toBe(true)
		t.expect(g.controls.A.i1).toBeNil()
		t.expect(g.controls.A.i500).toBeNil()
		g.world.stop()
	end)
end)

return nil
