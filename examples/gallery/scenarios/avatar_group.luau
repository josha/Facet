--!strict
-- A manual gallery transport uses an existing picture, not a simulated headshot fetch.
local function initialMembers()
	return {
		{ id = "ada", name = "Ada Quill", key = "portrait-a", presence = "online" },
		{ id = "bo", name = "Bo Lane", key = "portrait-b", presence = "away" },
		{ id = "noel", name = "Émile Noël", presence = "busy" },
		{ id = "cote", name = "Côte 東京", presence = "offline" },
		{ id = "kai", name = "Kai North" },
		{ id = "ivy", name = "Ivy Moss" },
	}
end
return {
	title = "Player groups",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local provider, release = ctx.app.newResourceProvider({ bind = false })
		local items, variant = Compose.cell(initialMembers()), Compose.cell("stacked")
		local size, activations = Compose.cell("regular"), Compose.cell(0)
		local rootPath, controller, record
		local function complete()
			for _, request in provider.pendingRequests() do
				provider.complete(request.key, request.generation, "rbxassetid://75342910516929")
			end
		end
		local function report()
			if not rootPath or not controller or not record then
				return nil
			end
			ctx.presenter.refresh()
			local path = rootPath .. "/Variant/[" .. variant:peek() .. "]/Team"
			local dump = record.dump()
			local faces, readyImages = {}, 0
			for _, id in dump.shown do
				for _, member in items:peek() do
					if member.id == id then
						local source = if member.key then "key:" .. member.key else "initials"
						local face = path .. "/Members/[" .. id .. "]/" .. id .. "/Source/[" .. source .. "]/Face"
						faces[id] = controller.rectOf(face)
						if controller.rectOf(face .. "/Picture/then/Picture") then
							readyImages += 1
						end
					end
				end
			end
			return {
				group = dump,
				rect = controller.rectOf(path),
				faces = faces,
				overflowRect = controller.rectOf(path .. "/Overflow/then/More+target/More"),
				imageBranches = readyImages,
				providerHandles = provider.counters().handles,
				activations = activations:peek(),
			}
		end
		local function reorder()
			local nextItems = table.clone(items:peek())
			local first = table.remove(nextItems, 1)
			table.insert(nextItems, first)
			items:set(nextItems)
			return report()
		end
		local function fewer()
			local nextItems = table.clone(items:peek())
			if #nextItems > 1 then
				table.remove(nextItems)
			end
			items:set(nextItems)
			return report()
		end
		local function restore()
			items:set(initialMembers())
			return report()
		end
		local function setVariant(value)
			variant:set(value)
			return report()
		end
		local function setSize(value)
			size:set(value)
			return report()
		end
		local function source()
			local nextItems = table.clone(items:peek())
			for index, member in nextItems do
				if member.id == "ada" then
					local changed = table.clone(member)
					changed.key = if member.key == "portrait-a" then "portrait-alternate" else "portrait-a"
					nextItems[index] = changed
				end
			end
			items:set(nextItems)
			return report()
		end
		local function section()
			Compose.cleanup(ctx.presenter.onTick(complete))
			Compose.cleanup(function()
				rootPath, controller, record = nil, nil, nil
			end)
			local root = UI.VStack("GroupRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Players together", textSize = "heading", width = UI.fill() }),
				UI.Text("Note")({
					text = "Faces keep their identity when reordered. Open the count to see everyone.",
					width = UI.fill(),
				}),
				UI.ForEach("Variant")({
					items = function(use)
						return { use(variant) }
					end,
					key = function(value)
						return value
					end,
					row = function(value)
						return UI.AvatarGroup("Team")({
							items = items,
							provider = provider,
							controlSize = size,
							layout = if value == "spread" then "spread" else "stacked",
							overflow = if value == "ellipsis" then "ellipsis" else "count",
							onOverflow = function()
								activations:set(activations:peek() + 1)
							end,
							ref = function(value)
								record = value
							end,
						})
					end,
				}),
				UI.HStack("RosterActions")({
					gap = "s",
					wrap = true,
					UI.Button("Reorder")({ label = "Reorder", onActivate = reorder }),
					UI.Button("Fewer")({ label = "Fewer", onActivate = fewer }),
					UI.Button("Restore")({ label = "Restore", onActivate = restore }),
					UI.Button("ChangePicture")({ label = "Change picture", onActivate = source }),
				}),
				UI.HStack("LayoutActions")({
					gap = "s",
					wrap = true,
					UI.Button("Stacked")({
						label = "Stacked",
						onActivate = function()
							setVariant("stacked")
						end,
					}),
					UI.Button("Spread")({
						label = "Spread",
						onActivate = function()
							setVariant("spread")
						end,
					}),
					UI.Button("Ellipsis")({
						label = "Ellipsis",
						onActivate = function()
							setVariant("ellipsis")
						end,
					}),
					UI.Button("Compact")({
						label = "Compact",
						onActivate = function()
							setSize("compact")
						end,
					}),
					UI.Button("Large")({
						label = "Large",
						onActivate = function()
							setSize("large")
						end,
					}),
				}),
				UI.Text("Activations")({
					text = function(use)
						return `Opened the group {use(activations)} times`
					end,
				}),
			})
			return ctx.Facet.contribution.attach(root, {
				bindController = function(value)
					controller = value
				end,
				syncGeometry = function(_, node)
					if node then
						rootPath = node.path
					end
				end,
			})
		end
		return {
			section = section,
			screen = function()
				return UI.Screen("AvatarGroup")({
					padding = "m",
					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), section() }),
				})
			end,
			report = report,
			dispose = release,
			steps = {
				reorder = reorder,
				fewer = fewer,
				restore = restore,
				source = source,
				stacked = function()
					return setVariant("stacked")
				end,
				spread = function()
					return setVariant("spread")
				end,
				ellipsis = function()
					return setVariant("ellipsis")
				end,
				compact = function()
					return setSize("compact")
				end,
				large = function()
					return setSize("large")
				end,
			},
			reset = function()
				items:set(initialMembers())
				variant:set("stacked")
				size:set("regular")
				activations:set(0)
			end,
		}
	end,
}
