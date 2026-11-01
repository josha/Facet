--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))

local commands = {}

export type Submit = {
	id: string,

	apply: (() -> ())?,

	decide: () -> (boolean, string?),

	revert: (() -> ())?,
	confirm: (() -> ())?,

	after: ((ok: boolean) -> ())?,
}

export type Feedback = { type: string, reason: string?, context: { command: string } }
export type Entry = { id: string, ok: boolean, reason: string? }
export type Opts = {
	Compose: ComposeModule,
	clock: { read after: (number, () -> ()) -> unknown },
	feedback: ((Feedback) -> ())?,
	strings: { read t: (string) -> string }?,
	latency: number?,
	toast: ((string, string) -> ())?,
}

function commands.new(opts: Opts)
	local Compose = opts.Compose
	local clock = opts.clock
	local feedback = opts.feedback
	local S = opts.strings
	local latency: number = opts.latency or 0.25

	local statuses: { [string]: Value<string> } = {}
	local reasons: { [string]: Value<string> } = {}
	local inFlight: { [string]: boolean } = {}
	local log: { Entry } = {}
	local self = { log = log }

	local function statusSignal(id: string): Value<string>
		local existing = statuses[id]
		if existing == nil then
			existing = Compose.cell("idle")
			statuses[id] = existing
		end
		return existing
	end

	local function reasonSignal(id: string): Value<string>
		local existing = reasons[id]
		if existing == nil then
			existing = Compose.cell("")
			reasons[id] = existing
		end
		return existing
	end

	function self.status(id: string): Value<string>
		return statusSignal(id)
	end

	function self.reason(id: string): Value<string>
		return reasonSignal(id)
	end

	function self.isPending(id: string): boolean
		return statusSignal(id):peek() == "pending"
	end

	local function toast(id: string, message: string)
		local show = opts.toast
		if show ~= nil then
			show(id, message)
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

	function self.dump(): { Entry }
		local out: { Entry } = {}
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
