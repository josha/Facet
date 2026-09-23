--!strict

local example = { title = "Confirmation Dialog" }
function example.build(ctx: any)
	local UI, Compose = ctx.UI, ctx.Compose
	local Host = ctx.Host
	local Compose = ctx.Compose
	local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
	local UDim, UDim2, Vector2, Color3, Enum =
		nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
	local built: any = {
		deletePath = "/DangerScreen/Page/Delete",
		restorePath = "/DangerScreen/Page/Restore",
		outcomePath = "/DangerScreen/Page/Outcome",
		titlePath = "/DangerScreen/Page/Title",
		confirmPath = "/ConfirmDialog/Center/Card/Actions/Order/[Confirm]/Confirm",
		cancelPath = "/ConfirmDialog/Center/Card/Actions/Order/[Cancel]/Cancel",
		cardPath = "/ConfirmDialog/Center/Card",
		dispose = function() end,
	}
	local result = Compose.cell("none")
	local hasSave = Compose.cell(true)
	local open = Compose.cell(false)
	local outcome = Compose.formula(function(use)
		if use(result) == "confirmed" then
			return "Deleted. The slot is empty now."
		end
		if use(result) == "cancelled" then
			return "Kept. Nothing was deleted."
		end
		return "This slot holds a save. Deleting it cannot be undone."
	end)
	local function openDialog()
		open:set(true)
	end
	local function restore()
		ctx.runtime:batch(function()
			hasSave:set(true)
			result:set("none")
		end)
	end
	function built.result()
		return result:peek()
	end
	function built.hasSave()
		return hasSave:peek()
	end
	function built.outcomeText()
		return outcome:peek()
	end
	built.openDialog, built.restore = openDialog, restore
	function built.screen()
		return Host.Frame({
			Name = "DangerScreen",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Host.UIPadding({
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			Host.ScrollingFrame({
				Name = "Page",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextSize = 28,
					Text = function(use)
						return if use(hasSave) then "Save Slot 1 — Rally Stage 3, 42%" else "Save Slot 1 — empty"
					end,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Outcome",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = outcome,
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Button({
					LayoutOrder = 3,
					Name = "Delete",
					label = "Delete Save",
					enabled = hasSave,
					onActivate = openDialog,
				}),
				UI.Button({
					LayoutOrder = 4,
					Name = "Restore",
					label = "Restore the save",
					onActivate = restore,
				}),
			}),
			UI.Alert({
				Name = "ConfirmDialog",
				title = "Delete this save?",
				severity = "critical",
				message = "This cannot be undone.",
				isPresented = open,
				actions = {
					{
						id = "Confirm",
						label = "Delete Save",
						compactLabel = "Delete",
						role = "destructive",
						onActivate = function()
							ctx.runtime:batch(function()
								result:set("confirmed")
								hasSave:set(false)
							end)
						end,
					},
					{
						id = "Cancel",
						label = "Cancel",
						role = "cancel",
						onActivate = function()
							result:set("cancelled")
						end,
					},
				},
			}),
		})
	end
	return built
end
return example
