--!strict

local order = {}

order.RESOLVE_AFTER = 0.6
order.READY_AFTER = 4.0

function order.new(opts: any)
	local Compose = opts.Compose

	local batch = opts.batch
	local clock = opts.clock

	local status = Compose.cell("idle")
	local mode = Compose.cell("paid")
	local blendId = Compose.cell(nil :: string?)
	local isReady = Compose.cell(false)
	local reason = Compose.cell(nil :: string?)
	local paymentsEnabled = Compose.cell(opts.paymentsEnabled ~= false)
	local attempts = 0
	local readyHandle: any = nil
	local listeners: { (string, any) -> () } = {}

	local self = {}
	self.status = status
	self.mode = mode
	self.blendId = blendId
	self.isReady = isReady
	self.reason = reason
	self.paymentsEnabled = paymentsEnabled
	self.price = "49 Credits"
	self.guardReasonKey = "guard.paymentsDisabled"
	self.rejectAt = opts.rejectAt or { 1 }

	local function rejects(attempt: number): boolean
		for _, at in self.rejectAt do
			if at == attempt then
				return true
			end
		end
		return false
	end

	local function emit(event: string, info: any)
		for _, fn in listeners do
			fn(event, info)
		end
	end

	function self.onEvent(fn: (string, any) -> ()): () -> ()
		table.insert(listeners, fn)
		return function()
			local index = table.find(listeners, fn)
			if index ~= nil then
				table.remove(listeners, index)
			end
		end
	end

	function self.guard(): { allowed: boolean, reasonKey: string? }
		if paymentsEnabled:peek() then
			return { allowed = true }
		end
		return { allowed = false, reasonKey = self.guardReasonKey }
	end

	function self.setPaymentsEnabled(on: boolean)
		paymentsEnabled:set(on == true)
	end

	function self.placeOrder(id: string, requestedMode: string): { started: boolean, reasonKey: string? }
		local guard = self.guard()
		if not guard.allowed then
			return { started = false, reasonKey = guard.reasonKey }
		end
		if status:peek() == "pending" then
			return { started = false, reasonKey = nil }
		end
		if readyHandle ~= nil then
			readyHandle.cancel()
			readyHandle = nil
		end
		batch(function()
			blendId:set(id)
			mode:set(requestedMode)
			status:set("pending")
			isReady:set(false)
			reason:set(nil)
		end)
		emit("pending", { blendId = id, mode = requestedMode })
		clock.after(order.RESOLVE_AFTER, function()
			attempts += 1
			if rejects(attempts) then
				batch(function()
					status:set("rejected")
					reason:set("counterClosed")
				end)
				emit("rejected", { blendId = id, mode = requestedMode, reason = "counterClosed" })
				return
			end
			status:set("confirmed")
			emit("confirmed", { blendId = id, mode = requestedMode })
			readyHandle = clock.after(order.READY_AFTER, function()
				isReady:set(true)
				emit("ready", { blendId = id, mode = requestedMode })
			end, "order-ready")
		end, "order-resolve")
		return { started = true }
	end

	function self.acknowledge()
		if status:peek() == "rejected" then
			batch(function()
				status:set("idle")
				reason:set(nil)
			end)
		end
	end

	function self.clear()
		if readyHandle ~= nil then
			readyHandle.cancel()
			readyHandle = nil
		end
		batch(function()
			status:set("idle")
			isReady:set(false)
			reason:set(nil)
			blendId:set(nil)
		end)
	end

	function self.attempts(): number
		return attempts
	end

	function self.reset()
		attempts = 0
		paymentsEnabled:set(opts.paymentsEnabled ~= false)

		mode:set("paid")
		self.clear()
	end

	return self
end

return order
