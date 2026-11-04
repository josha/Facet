--!strict

local Compose = require "../core"
local Devices = require "./devices"
local UI = require "./ui"

export type Variant = { title: string, source: string }
export type Draft = { message: string, variants: { Variant }, pick: (number) -> string, discard: (() -> ())? }
export type Render = (string, Devices.Profile, Compose.Node) -> () -> ()

return function(ui: UI.UI, parent: Compose.Node, device: Devices.Profile, draft: Draft, render: Render, close: () -> ())
	assert(#draft.variants == 2 or #draft.variants == 3, "Compare two or three Design drafts")
	local Theme = require "./theme"(ui)
	local root = Theme.frame("DesignDrafts", Theme.color.canvas)
	Theme.place(root, parent, ui.values.udim2(1, 0, 1, -140))
	local status = Theme.label("Drafts · Choose one to save", Theme.color.secondary, Theme.size.small)
	ui.set(status, "Name", "DraftStatus")
	Theme.place(status, root, ui.values.udim2(1, -152, 0, 32))
	local discard = Theme.button("DiscardDrafts", "Discard drafts")
	Theme.place(discard, root, ui.values.udim2(0, 140, 0, 32), ui.values.udim2(1, -140, 0, 0))
	local body = Theme.frame "DraftComparison"
	Theme.place(body, root, ui.values.udim2(1, 0, 1, -40), ui.values.udim2(0, 0, 0, 40))
	Theme.list(body, ui.values.enum("FillDirection", "Horizontal"), 12)
	local releases: { () -> () } = {}
	local connections: { UI.Connection } = {}
	local disposed, busy = false, false
	table.insert(
		connections,
		ui.connect(discard, "Activated", function()
			if not busy then
				close()
			end
		end)
	)
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		local discard = draft.discard
		if discard then
			ui.runtime.scheduler(ui.owner).after(0, function()
				pcall(discard)
			end)
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, release in releases do
			release()
		end
		ui.destroy(root)
	end
	local ok, failure = pcall(function()
		for index, variant in draft.variants do
			local card = Theme.frame("Draft" .. index, Theme.color.panel)
			ui.set(card, "LayoutOrder", index)
			ui.set(
				card,
				"Size",
				ui.values.udim2(1 / #draft.variants, -12 * (#draft.variants - 1) / #draft.variants, 1, 0)
			)
			ui.set(card, "Parent", body)
			local title = Theme.label(variant.title, Theme.color.text, Theme.size.text, Theme.font.bold)
			Theme.place(title, card, ui.values.udim2(1, 0, 0, 28))
			local preview = Theme.frame "DraftPreview"
			Theme.place(preview, card, ui.values.udim2(1, 0, 1, -76), ui.values.udim2(0, 0, 0, 32))
			table.insert(releases, render(variant.source, device, preview))
			local pick = Theme.button("ChooseVariant", "Choose this variant", Theme.color.white)
			ui.set(pick, "BackgroundTransparency", 0)
			ui.set(pick, "BackgroundColor3", Theme.color.accent)
			Theme.place(pick, card, ui.values.udim2(1, -16, 0, 32), ui.values.udim2(0, 8, 1, -36))
			table.insert(
				connections,
				ui.connect(pick, "Activated", function()
					if busy then
						return
					end
					busy = true
					ui.set(status, "Text", "Saving selected variant...")
					ui.runtime.scheduler(ui.owner).after(0, function()
						if disposed then
							return
						end
						local chosen = pcall(draft.pick, index)
						if disposed then
							return
						end
						busy = false
						if chosen then
							close()
						else
							ui.set(status, "Text", "Variant request failed; check source sync")
						end
					end)
				end)
			)
		end
	end)
	if not ok then
		dispose()
		error(failure, 0)
	end
	return { dispose = dispose }
end
