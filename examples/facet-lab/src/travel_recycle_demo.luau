--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type Destination = typeof(require("@repo/tools/typecheck/aliases").ZoomDestinationCell)

return function(UI: Controls, Host: Host, C: ComposeModule): Frame
	local keys, items = C.cell({ 1, 2 }), C.cell({ 40 })
	local targets: { [number]: GuiObject } = {}
	local park = Host.Frame { Name = "Park", Size = UDim2.new(1, 0, 0, 64), ClipsDescendants = true }
	local destination: Destination = C.cell(park :: GuiObject)
	local serial, generation = 40, 1
	local grid = UI.VirtualGrid {
		Name = "RecycledTargets",
		from = keys,
		key = function(value: number): number
			return value
		end,
		columns = 2,
		itemSize = 64,
		mode = "all" :: "all",
		Size = UDim2.new(1, 0, 0, 100),
		render = function(current): GuiObject
			local key = current:peek()
			local target = UI.Button {
				Name = `Target{key}`,
				label = `Slot {key}`,
				ClipsDescendants = true,
				Size = UDim2.fromScale(1, 1),
			}
			targets[key] = target
			return target
		end,
	}
	return UI.VStack(({
		Name = "RecycledTravel",
		width = "fill" :: "fill",
		gap = "s",
		UI.HStack {
			gap = "s",
			UI.Button {
				Name = "NewItem",
				label = "New item",
				onActivate = function()
					serial += 1
					destination:set(park)
					items:set({ serial })
				end,
			},
			UI.Button {
				Name = "ChooseTarget",
				label = "Choose target",
				onActivate = function()
					local key = keys:peek()[1]
					if key then
						destination:set(assert(targets[key]))
					end
				end,
			},
			UI.Button {
				Name = "ReplaceTargets",
				label = "Replace targets",
				onActivate = function()
					generation += 2
					keys:set({ generation, generation + 1 })
					destination:set(assert(targets[generation]))
				end,
			},
			UI.Button {
				Name = "RemoveTargets",
				label = "Remove targets",
				onActivate = function()
					keys:set({})
				end,
			},
		} :: unknown,
		park :: unknown,
		grid :: unknown,
		C.OrderedCollection {
			from = items,
			key = function(id: number): number
				return id
			end,
			render = function(current)
				return UI.Travel {
					Name = `Carrier{current:peek()}`,
					destination = destination,
					path = "arc" :: "arc",
					content = function(): GuiObject
						return UI.Text {
							Name = `Tile{current:peek()}`,
							text = "A",
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
						}
					end,
				}
			end,
		} :: unknown,
		UI.Text {
			text = "Choose a target. Replace its keys or remove it during travel or after landing. The carrier must disappear without an error. New item starts a fresh lifetime.",
			wrap = true,
		} :: unknown,
	} :: unknown) :: StackProps)
end
