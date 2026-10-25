--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

type Lease = { count: number, before: boolean, suspended: ComposeTypes.Cell<boolean> }

local leases = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiService]: Lease }

local function leaseFor(ctx: Types.Context, gui: GuiService): Lease
	local lease = leases[gui]
	if lease == nil then
		lease = { count = 0, before = true, suspended = ctx.Compose.cell(false) }
		leases[gui] = lease
	end
	return lease :: Lease
end

local function hold(ctx: Types.Context): () -> ()
	local gui = ctx.config.guiService
	if gui == nil then
		return function() end
	end
	local lease = leaseFor(ctx, gui)
	if lease.count == 0 then
		lease.before = gui.TouchControlsEnabled
	end
	lease.count += 1
	gui.TouchControlsEnabled = false
	lease.suspended:set(true)
	local released = false
	return function()
		if released then
			return
		end
		released = true
		lease.count -= 1
		if lease.count == 0 then
			gui.TouchControlsEnabled = lease.before
			lease.suspended:set(false)
		end
	end
end

local function suspended(ctx: Types.Context): ComposeTypes.Readable<boolean>
	local gui = ctx.config.guiService
	return if gui then leaseFor(ctx, gui).suspended else ctx.Compose.cell(false)
end

return { hold = hold, suspended = suspended }
