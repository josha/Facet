--!strict
local COPY = {
	title = "Steps",
	refuse = "Refuse changes",
	narrow = "Narrow",
	cart = "Cart",
	shipping = "Shipping",
	shippingNote = "Address and speed",
	payment = "Payment",
	paymentNote = "Card declined",
	review = "Review",
}

return {
	title = "Steps",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local refuse = Compose.cell(false)
		local current = Compose.cell("ship" :: string?)
		local steps = {
			{ id = "cart", label = copy.cart, state = "complete" :: "complete", navigable = true },
			{ id = "ship", label = copy.shipping, description = copy.shippingNote, navigable = true },
			{
				id = "pay",
				label = copy.payment,
				description = copy.paymentNote,
				state = "error" :: "error",
				navigable = true,
			},
			{ id = "review", label = copy.review },
		}
		local function select(id: string)
			if not refuse:peek() then
				current:set(id)
			end
		end
		local function section()
			return Host.Frame "Steps" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text({
					Name = "Title",
					LayoutOrder = 1,
					text = copy.title,
					textRole = "heading",
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Toggle({ Name = "Refuse", LayoutOrder = 2, label = copy.refuse, value = refuse }),
				UI.StepIndicator({
					Name = "Checkout",
					LayoutOrder = 3,
					steps = steps,
					current = current,
					onSelect = select,
				}),
				UI.Text({
					Name = "NarrowTitle",
					LayoutOrder = 4,
					text = copy.narrow,
					textRole = "label",
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame "NarrowBox" {
					LayoutOrder = 5,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(0.5, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.StepIndicator({ Name = "Compact", steps = steps, current = current, onSelect = select }),
				},
			}
		end
		return {
			section = section,
			screen = function()
				return Host.ScrollingFrame "StepsScreen" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 6,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					section(),
				}
			end,
			steps = {
				select = select,
				refuse = function()
					refuse:set(not refuse:peek())
				end,
			},
			report = function()
				return { current = current:peek(), refuse = refuse:peek() }
			end,
		}
	end,
}
