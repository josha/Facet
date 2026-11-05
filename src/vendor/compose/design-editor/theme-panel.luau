--!strict

local Compose = require "../core"
local UI = require "./ui"

export type Value = string | number
export type Field = {
	id: string,
	label: string,
	kind: "color" | "type" | "spacing",
	read: (Compose.Use) -> Value,
	minimum: number?,
	maximum: number?,
}
export type Store = { fields: { Field }, write: (string, Value) -> boolean }

local function create(ui: UI.UI, parent: Compose.Node, store: Store)
	local Theme = require "./theme"(ui)
	local root = Theme.scroller "DesignTheme"
	ui.set(root, "Size", ui.values.udim2(1, 0, 1, 0))
	ui.set(root, "Visible", false)
	ui.set(root, "Parent", parent)
	Theme.pad(root, 12, 12, 4, 12)
	Theme.list(root, ui.values.enum("FillDirection", "Vertical"), 8)
	local status = Theme.label("Shared tokens", Theme.color.secondary, Theme.size.small)
	ui.set(status, "Name", "ThemeStatus")
	ui.set(status, "Size", ui.values.udim2(1, 0, 0, 24))
	ui.set(status, "LayoutOrder", 0)
	ui.set(status, "Parent", root)
	local connections: { UI.Connection } = {}
	local disposed = false
	local function write(id: string, value: Value)
		assert(not disposed, "Theme is closed")
		local selected: Field? = nil
		for _, field in store.fields do
			if field.id == id then
				selected = field
				break
			end
		end
		local field = assert(selected, "Unknown theme token: " .. id)
		local valid = if field.kind == "color"
			then type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
			else type(value) == "number"
				and value == value
				and value >= (field.minimum or 0)
				and value <= (field.maximum or 512)
		assert(valid, "Enter #RRGGBB or a value within the token's range")
		assert(store.write(id, value), "Token change failed; source preserved")
		ui.set(status, "Text", "Shared tokens saved")
	end
	local owner = Compose.createRootOwner(function()
		for index, field in store.fields do
			local row = Theme.frame(field.id)
			ui.set(row, "Size", ui.values.udim2(1, 0, 0, 60))
			ui.set(row, "LayoutOrder", index)
			ui.set(row, "Parent", root)
			local label = Theme.label(field.label, Theme.color.secondary, Theme.size.small)
			Theme.place(label, row, ui.values.udim2(1, 0, 0, 24))
			local input = Theme.field ""
			ui.set(input, "Name", "TokenValue")
			Theme.place(input, row, ui.values.udim2(1, 0, 0, 32), ui.values.udim2(0, 0, 0, 26))
			Compose.watch(function(use: Compose.Use)
				ui.set(input, "Text", tostring(field.read(use)))
			end)
			table.insert(
				connections,
				ui.connect(input, "FocusLost", function()
					local text = ui.text(input, "Text")
					local value: Value? = if field.kind == "color" then string.upper(text) else tonumber(text)
					local valid = if field.kind == "color"
						then type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
						else type(value) == "number"
							and value == value
							and value >= (field.minimum or 0)
							and value <= (field.maximum or 512)
					if not valid or value == nil then
						ui.set(status, "Text", "Enter #RRGGBB or a value within the token's range")
						return
					end
					local chosen = value
					ui.runtime.scheduler(ui.owner).after(0, function()
						if disposed then
							return
						end
						local ok, failure = pcall(write, field.id, chosen)
						if not disposed then
							ui.set(status, "Text", if ok then "Shared tokens saved" else tostring(failure))
						end
					end)
				end)
			)
		end
	end, ui.runtime.reactor)
	local release = Compose.owner.own(ui.owner, owner.dispose)
	return {
		root = root,
		write = write,
		dispose = function()
			disposed = true
			release()
			for _, connection in connections do
				connection:Disconnect()
			end
			ui.destroy(root)
		end,
	}
end

return { create = create }
