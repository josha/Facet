--!strict
-- OrderService (spec §3, §8): `placeOrder(blendId, mode)` and the scripted
-- ready flip.
--
-- Production is a server command plus a replicated status (responsibility
-- ledger); the pay-shaped path ends at `PromptProductPurchase`, which is a HOST
-- SHEET — so nothing here imitates payment chrome and the audit claims no
-- parity for it (spec §16).
--
-- Three fixtures:
--   * `counterClosed` rejects the FIRST order attempt, so the rejection path is
--     reachable by pressing the on-screen CTA twice and needs no test seam;
--   * the pour is READY 4.0 s after a confirm, on the injected clock;
--   * `payments = { enabled = false, reasonKey = "guard.paymentsDisabled" }` is
--     the guard. While it holds, the CTA stays visible and inspectable and
--     explains itself — a blocked verb that vanished would be a silent state.

local order = {}

order.RESOLVE_AFTER = 0.6
order.READY_AFTER = 4.0

function order.new(opts: any)
	local core = opts.core
	local scope = opts.scope
	local clock = opts.clock

	local status = core:signal("idle") -- idle | pending | confirmed | rejected
	local mode = core:signal("paid") -- paid | redeem
	local blendId = core:signal(nil :: string?)
	local isReady = core:signal(false)
	local reason = core:signal(nil :: string?)
	local paymentsEnabled = core:signal(opts.paymentsEnabled ~= false)
	local attempts = 0
	local readyHandle: any = nil
	local listeners: { (string, any) -> () } = {}
	scope:own(function()
		status:dispose()
		mode:dispose()
		blendId:dispose()
		isReady:dispose()
		reason:dispose()
		paymentsEnabled:dispose()
	end)

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

	-- the guard, as a VALUE rather than a branch: a caller asks, and the answer
	-- carries the reason key the alert body is written from
	function self.guard(): { allowed: boolean, reasonKey: string? }
		if paymentsEnabled:get() then
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
		if status:get() == "pending" then
			return { started = false, reasonKey = nil }
		end
		if readyHandle ~= nil then
			readyHandle.cancel()
			readyHandle = nil
		end
		core:transaction(function()
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
				core:transaction(function()
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

	-- the CTA returns to idle: after a rejection has been read, and when the
	-- Order-Placed surface is dismissed
	function self.acknowledge()
		if status:get() == "rejected" then
			core:transaction(function()
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
		core:transaction(function()
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
		--[[ `mode` TOO, and it was the one observable a reset used to leave behind.
			`clear()` is the END-OF-ORDER verb — it retires the status, the ready flag
			and the blend but deliberately keeps the mode the order was placed in, so
			the Order-Placed card can still say which kind of pour it was while it
			fades. A RESET is a different act: it returns the world to the seed, and a
			world seeded with `orderMode=redeem` is a world that redeemed something.
			Found by driving the whole task loop to its free pour and then pressing
			"Serve another customer" — the reset pin's old drive never placed a redeem
			order, so the dump differed by exactly this field and nothing said so. ]]
		mode:set("paid")
		self.clear()
	end

	return self
end

return order
