--!strict
local Types = require("./types")

type Lease = { count: number, restore: { () -> () } }

local leases = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [unknown]: Lease }

local function lease(key: unknown, suspend: (restore: { () -> () }) -> ()): () -> ()
	local held = leases[key]
	if held == nil then
		held = { count = 0, restore = {} }
		leases[key] = held
	end
	local current = held :: Lease
	current.count += 1
	if current.count == 1 then
		suspend(current.restore)
	end
	local released = false
	return function()
		if released then
			return
		end
		released = true
		current.count -= 1
		if current.count == 0 then
			leases[key] = nil
			for index = #current.restore, 1, -1 do
				current.restore[index]()
			end
		end
	end
end

local function touch(gui: GuiService?): () -> ()
	if gui == nil then
		return function() end
	end
	return lease(gui, function(restore)
		local before = gui.TouchControlsEnabled
		gui.TouchControlsEnabled = false
		table.insert(restore, function()
			gui.TouchControlsEnabled = before
		end)
	end)
end

local function hold(config: Types.Config): () -> ()
	local gameplay = config.gameplay
	if gameplay == nil then
		return function() end
	end
	local contexts: { InputContext } = gameplay.contexts or {}
	local controls: { GuiObject } = gameplay.controls or {}
	local releaseInput = lease(gameplay, function(restore)
		for _, context in contexts do
			local before = context.Enabled
			context.Enabled = false
			table.insert(restore, function()
				context.Enabled = before
			end)
		end
		for _, control in controls do
			local before = control.Visible
			control.Visible = false
			table.insert(restore, function()
				control.Visible = before
			end)
		end
	end)
	local releaseTouch = touch(config.guiService)
	return function()
		releaseTouch()
		releaseInput()
	end
end

return { hold = hold, touch = touch }
