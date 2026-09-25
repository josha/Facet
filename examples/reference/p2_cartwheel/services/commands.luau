--!strict

local commands = {}

export type Submit = {
	id: string,

	apply: (() -> ())?,

	decide: () -> (boolean, string?),

	revert: (() -> ())?,
	confirm: (() -> ())?,

	after: ((ok: boolean) -> ())?,
}

function commands.new(opts: any): any
	local Compose = opts.Compose
	local clock = opts.clock
	local feedback = opts.feedback
	local S = opts.strings
	local latency: number = opts.latency or 0.25

	local statuses: { [string]: any } = {}
	local reasons: { [string]: any } = {}
	local inFlight: { [string]: boolean } = {}
	local log: { any } = {}
	local self: any = { log = log }

	local function statusSignal(id: string): any
		local existing = statuses[id]
		if existing == nil then
			existing = Compose.cell("idle")
			statuses[id] = existing
		end
		return existing
	end

	local function reasonSignal(id: string): any
		local existing = reasons[id]
		if existing == nil then
			existing = Compose.cell("")
			reasons[id] = existing
		end
		return existing
	end

	function self.status(id: string): any
		return statusSignal(id)
	end

	function self.reason(id: string): any
		return reasonSignal(id)
	end

	function self.isPending(id: string): boolean
		return statusSignal(id):peek() == "pending"
	end

	local function toast(id: string, message: string)
		if opts.toast ~= nil then
			opts.toast(id, message)
		end
	end

	local function emit(kind: string, id: string, reason: string?)
		if feedback ~= nil then
			feedback({ type = kind, reason = reason, context = { command = id } })
		end
	end

	function self.submit(spec: Submit): boolean
		if inFlight[spec.id] then
			return false
		end
		inFlight[spec.id] = true
		statusSignal(spec.id):set("pending")
		reasonSignal(spec.id):set("")
		if spec.apply ~= nil then
			spec.apply()
		end
		clock.after(latency, function()
			local ok, reasonKey = spec.decide()
			inFlight[spec.id] = false
			if ok then
				if spec.confirm ~= nil then
					spec.confirm()
				end
				statusSignal(spec.id):set("confirmed")
				emit("commit", spec.id)
			else
				if spec.revert ~= nil then
					spec.revert()
				end
				local key = reasonKey or "reject.fallback"
				local message = if S ~= nil then S.t(key) else key
				reasonSignal(spec.id):set(message)
				statusSignal(spec.id):set("rejected")
				toast(spec.id, message)
				emit("reject", spec.id, key)
			end
			table.insert(log, { id = spec.id, ok = ok, reason = reasonKey })
			if spec.after ~= nil then
				spec.after(ok)
			end
		end)
		return true
	end

	function self.dump(): any
		local out = {}
		for _, entry in log do
			table.insert(out, { id = entry.id, ok = entry.ok, reason = entry.reason })
		end
		return out
	end

	function self.dispose()
		statuses = {}
		reasons = {}
	end

	return self
end

return table.freeze(commands)
