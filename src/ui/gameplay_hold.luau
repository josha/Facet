--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

type Lease = {
	touches: number,
	suspensions: number,
	before: boolean,
	watch: RBXScriptConnection?,
	suspended: ComposeTypes.Value<boolean>,
}

local leases: { [GuiService]: Lease } = setmetatable({}, { __mode = "k" })

local function leaseFor(ctx: Types.Context, gui: GuiService): Lease
	local lease = leases[gui]
	if lease == nil then
		local created: Lease = {
			touches = 0,
			suspensions = 0,
			before = true,
			suspended = ctx.Compose.cell<<boolean>>(false),
		}
		leases[gui] = created
		return created
	end
	return lease
end

local function hold(ctx: Types.Context, gui: GuiService?, suspends: boolean): () -> ()
	if gui == nil then
		return function() end
	end
	local lease = leaseFor(ctx, gui)
	if lease.touches == 0 then
		lease.before = gui.TouchControlsEnabled
		lease.watch = gui:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(function()
			if gui.TouchControlsEnabled and lease.touches > 0 then
				lease.before = true
				gui.TouchControlsEnabled = false
			end
		end)
	end
	lease.touches += 1
	if gui.TouchControlsEnabled ~= false then
		gui.TouchControlsEnabled = false
	end
	if suspends then
		lease.suspensions += 1
		lease.suspended:set(true)
	end
	local released = false
	return function()
		if released then
			return
		end
		released = true
		if suspends then
			lease.suspensions -= 1
			if lease.suspensions == 0 then
				lease.suspended:set(false)
			end
		end
		lease.touches -= 1
		if lease.touches == 0 then
			if lease.watch then
				lease.watch:Disconnect()
				lease.watch = nil
			end
			if gui.TouchControlsEnabled ~= lease.before then
				gui.TouchControlsEnabled = lease.before
			end
		end
	end
end

local function suspended(ctx: Types.Context): ComposeTypes.ReadOnlyValue<boolean>
	local gui = ctx.config.guiService
	local source = if gui then leaseFor(ctx, gui).suspended else nil
	return ctx.Compose.formula(function(use: ComposeTypes.Use): boolean
		return if source then use(source) else false
	end)
end

return { hold = hold, suspended = suspended }
