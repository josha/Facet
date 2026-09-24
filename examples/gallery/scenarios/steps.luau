--!strict
--[[ Steps: `UI.StepIndicator` over a caller-owned current step
	(docs/reference/api.md#uistepindicator). Cart is complete, Payment carries an
	error, Review is informational only; the narrow copy beside it shows the
	summary and its list. A toggle refuses selections. ]]
local COPY = {
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
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local refuse = Compose.cell(false)
		local current = Compose.cell("ship" :: string?)
		local steps = {
			{ id = "cart", label = COPY.cart, state = "complete", navigable = true },
			{ id = "ship", label = COPY.shipping, description = COPY.shippingNote, navigable = true },
			{ id = "pay", label = COPY.payment, description = COPY.paymentNote, state = "error", navigable = true },
			{ id = "review", label = COPY.review },
		}
		local function select(id: string)
			if not refuse:peek() then
				current:set(id)
			end
		end
		local function section(): any
			return UI.VStack("Steps")({
				width = UI.fill(),
				gap = "m",
				UI.Toggle("Refuse")({ label = COPY.refuse, value = refuse }),
				UI.StepIndicator("Checkout")({ steps = steps, current = current, onSelect = select }),
				UI.Text("NarrowTitle")({ text = COPY.narrow, textSize = "label", width = UI.fill() }),
				UI.VStack("NarrowBox")({
					width = { type = "percent", fraction = 0.5 },
					UI.StepIndicator("Compact")({ steps = steps, current = current, onSelect = select }),
				}),
			})
		end
		return {
			section = section,
			screen = function()
				return UI.Screen("StepsScreen")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						section(),
					}),
				})
			end,
			steps = {},
		}
	end,
}
