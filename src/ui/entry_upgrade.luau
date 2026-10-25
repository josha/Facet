--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

export type Options = {
	gui: GuiService,
	panel: Instance,
	held: ComposeTypes.Cell<GuiObject?>,
	entry: () -> GuiObject?,
	ready: (ComposeTypes.Use) -> boolean,
	displayed: (Instance) -> boolean,
}

return function(ctx: Types.Context, options: Options)
	local Compose = ctx.Compose
	local gui, held = options.gui, options.held
	local descendants = Compose.cell(0)
	local selection = ctx.observe.SelectedObject(gui)
	ctx.runtime.connect(options.panel, "DescendantAdded", function()
		descendants:set(descendants:peek() + 1)
	end)
	Compose.watch(function(use: ComposeTypes.Use)
		use(descendants)
		use(selection)
		local current = use(held)
		if current == nil then
			return
		end
		if gui.SelectedObject ~= current then
			held:set(nil)
			return
		end
		if not options.ready(use) then
			return
		end
		local better = options.entry()
		if better and better ~= current then
			local size = use(ctx.observe.AbsoluteSize(better))
			local parent = use(ctx.observe.Parent(better))
			if parent and size.X > 0 and size.Y > 0 and options.displayed(better) then
				gui.SelectedObject = better
				if gui.SelectedObject == better then
					held:set(nil)
				end
			end
		end
	end)
end
