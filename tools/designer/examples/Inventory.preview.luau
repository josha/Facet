--!strict

local function inventory(ctx: any, populated: boolean, longNames: boolean): GuiObject
	local UI, Compose = ctx.UI, ctx.Compose
	local selected = Compose.cell(false)
	local quantity = Compose.cell(3)
	local filter = Compose.cell("")
	local details = Compose.cell(false)
	return UI.Screen "Inventory" {
		gap = "m",
		UI.Text { text = "Your next adventure", textRole = "title" },
		UI.Text { text = "Pack what matters. Leave room for discoveries.", role = "secondary", wrap = true },
		UI.TextInput { value = filter, placeholder = "Find equipment", clearButton = true },
		UI.ScrollView "Equipment" {
			width = "fill",
			height = "fill",
			gap = "s",
			if populated
				then UI.Card {
					title = if longNames
						then "The extraordinarily dependable explorer’s field pack"
						else "Explorer’s field pack",
					caption = "Ready for the trail",
					artwork = function()
						return UI.Text { text = "TRAIL / 01", textRole = "title", textAlign = "center" }
					end,
					onActivate = function()
						details:set(true)
					end,
				}
				else UI.Notice {
					title = "A fresh start",
					message = "Your pack is empty. Visit the outfitter to get ready.",
				},
			UI.Toggle { label = "Include emergency supplies", value = selected },
			UI.Stepper { value = quantity, min = 1, max = 10 },
			UI.AdaptiveStack "Actions" {
				gap = "s",
				UI.Button {
					label = "Inspect equipment",
					onActivate = function()
						details:set(true)
					end,
				},
				UI.Button {
					label = "Reset quantity",
					onActivate = function()
						quantity:set(3)
					end,
				},
			},
		},
		UI.Sheet {
			isPresented = details,
			detent = Compose.cell("medium"),
			title = "Equipment details",
			content = function()
				return UI.VStack {
					gap = "m",
					padding = "m",
					UI.Text { text = "Everything you need for a day outside.", wrap = true },
					UI.Button {
						label = "Done",
						onActivate = function()
							details:set(false)
						end,
					},
				}
			end,
		},
	}
end

return {
	name = "Trail inventory",
	previews = {
		{
			name = "Ready to explore",
			render = function(ctx)
				return inventory(ctx, true, false)
			end,
		},
		{
			name = "Empty pack",
			render = function(ctx)
				return inventory(ctx, false, false)
			end,
		},
		{
			name = "Long item names",
			render = function(ctx)
				return inventory(ctx, true, true)
			end,
		},
	},
}
