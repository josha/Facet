--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type Use = FacetTypes.Use
type NumberCell = FacetTypes.Value<number>
type ReadOnlyValue<T> = FacetTypes.ReadOnlyValue<T>
type Value<T> = FacetTypes.Value<T>
type Item = {
	id: string,
	name: string,
	description: string,
	image: string,
	price: number,
	currency: "Coins" | "Gems",
	owned: boolean,
}
type Model = {
	coins: NumberCell,
	gems: NumberCell,
	items: ReadOnlyValue<{ Item }>,
	confirmationThreshold: number,
	purchase: (itemId: string) -> { ok: boolean, reason: string? },
}

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local Compose = Facet.Compose
	local pending: Value<Item?> = Compose.cell(nil :: Item?)
	local busy = Compose.cell(false)
	local message = Compose.cell("")
	local confirmation = Compose.cell("")
	local purchased = Compose.cell(false)
	local function purchase(item: Item)
		busy:set(true)
		purchased:set(false)
		local result = model.purchase(item.id)
		message:set(if result.ok then "Purchased " .. item.name else result.reason or "Purchase failed")
		if result.ok then
			confirmation:set(message:peek())
		end
		purchased:set(result.ok)
		busy:set(false)
	end
	local itemsSpec: FacetTypes.KeyedCollectionSpec<Item, string> = {
		UI.fill(),
		from = model.items,
		key = "id",
		minColumnWidth = 240,
		minColumns = 2,
		itemSize = 320,
		measure = true,
		render = function(current: ReadOnlyValue<Item>): GuiObject
			return UI.VStack "ItemTile" {
				padding = "s",
				width = "fill",
				UI.Card "Item" {
					title = function(use: Use)
						return use(current).name
					end,
					image = function(use: Use)
						return use(current).image
					end,
					caption = function(use: Use)
						local item = use(current)
						return `{item.description}\n{item.price} {item.currency}`
					end,
					reveal = "always",
					primaryAction = {
						label = function(use: Use)
							return if use(current).owned then "Owned" else "Buy"
						end,
						enabled = function(use: Use)
							return not use(current).owned and not use(busy)
						end,
						onActivate = function()
							local item = current:peek()
							if item.price > model.confirmationThreshold then
								pending:set(item)
							else
								purchase(item)
							end
						end,
					},
				},
			}
		end,
	}
	local alertSpec: FacetTypes.AlertSpec<Item> = {
		item = pending,
		title = "Confirm purchase",
		message = function(item: Item)
			return `Buy {item.name} for {item.price} {item.currency}?`
		end,
		actions = function(_item: Item)
			return {
				{ id = "cancel", label = "Cancel", role = "cancel" :: "cancel" },
				{ id = "buy", label = "Buy", role = "default" :: "default", onActivate = purchase },
			}
		end,
	}
	return UI.Screen "Store" {
		padding = "m",
		gap = "m",
		UI.Text "Title" { text = "Item store", textRole = "title" },
		UI.HStack "Balances" {
			gap = "m",
			wrap = true,
			UI.Text "Coins" {
				text = function(use: Use)
					return `{use(model.coins)} Coins`
				end,
				textRole = "numeral",
			},
			UI.Text "Gems" {
				text = function(use: Use)
					return `{use(model.gems)} Gems`
				end,
				textRole = "numeral",
			},
		},
		UI.VirtualGrid "Items"(itemsSpec),
		UI.Text "Result" { text = message, textRole = "body", wrap = true },
		UI.Alert "ConfirmPurchase"(alertSpec),
		UI.Toast "PurchaseToast" {
			message = confirmation,
			isPresented = purchased,
			onPresentedChange = function(value)
				purchased:set(value)
			end,
		},
	}
end
