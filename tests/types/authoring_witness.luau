--!strict
local Facet = require("../../src")
local UI = Facet.View
local Card = Facet.component(function(ui, _props: {})
	local count, setCount = ui.state(0)
	local detent, setDetent = ui.state("medium")
	local enabled, setEnabled = ui.state(true)
	return UI.VStack({
		gap = "s",
		UI.Text("Native Luau"),
		UI.Text(function()
			return `Count: {count()}`
		end),
		UI.Toggle({ value = enabled, onChange = setEnabled }),
		UI.Slider({ value = count, min = 0, max = 10, onChange = setCount }),
		UI.Sheet({
			title = "Details",
			detent = detent,
			onDetentChange = setDetent,
			content = UI.Text("Details"),
			isPresented = enabled,
			onPresentedChange = setEnabled,
		}),
		UI.Alert({ title = "Continue?", isPresented = enabled, onPresentedChange = setEnabled }),
		UI.Button({
			label = "Add",
			onActivate = function(meta)
				if meta and meta.shift then
					setCount(function(n)
						return n + 10
					end)
				else
					setCount(count() + 1)
				end
			end,
		}),
	})
end)
local _description = Card({})
local _rows = UI.ForEach({
	items = function()
		return { { id = "a", title = "First" } }
	end,
	key = function(item)
		return item.id
	end,
	row = function(item)
		return UI.Text(function()
			return item().title
		end)
	end,
})

local Fancy = Facet.component(function(ui, props: { title: string } & Facet.ComponentChildren)
	local open, setOpen = ui.state(false)
	local progress = ui.animate(function()
		return if open() then 1 else 0
	end, "object")
	return UI.VStack({
		animation = { layout = "container" },
		UI.Toggle({ value = open, onChange = setOpen, animation = { layout = "object" } }),
		UI.When({ condition = open, UI.Text(props.title) }),
		UI.ZStack({ opacity = progress, animation = { scale = "object", opacity = false }, children = props.children }),
	})
end)
local _fancy = Fancy({ title = "Details", UI.Text("Child") })
local Row = Facet.component(function(_ui, item: () -> { id: string, name: string })
	return UI.Text(function()
		return item().name
	end)
end)
local _keyed = UI.ForEach({
	items = function()
		return { { id = "a", name = "A" } }
	end,
	key = "id",
	row = Row,
})
