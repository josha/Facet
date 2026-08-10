--!strict
-- EVERY MUTATION IS A COMMAND (spec §3): `idle -> pending -> confirmed |
-- rejected`, with no silent states. This is the one place that lifecycle lives,
-- so a screen never has to remember to disable its own button or to raise its
-- own toast — it hands over what to do and what to undo.
--
-- Pending is REAL, not a formality. A fake service could answer instantly, and
-- then "while pending the control disables and gains a Working… chip" would be a
-- state no player could ever see and no test could pin. So a command resolves
-- one `latency` of DOMAIN time after it is submitted: headlessly the suite steps
-- the clock across it, and in a live place the presenter's own tick does.
local commands = {}

export type Submit = {
	id: string,
	-- optimistic: run at submit, before anything is decided
	apply: (() -> ())?,
	-- the authority: returns (ok, reasonKey). A reasonKey names a string, so a
	-- rejection always has player-facing copy.
	decide: () -> (boolean, string?),
	-- put the view back (reject) / reconcile from truth (confirm)
	revert: (() -> ())?,
	confirm: (() -> ())?,
	-- an optional consequence that must run on the confirming frame (the
	-- celebration opens from here, so `celebrate` and the state it celebrates
	-- share one causal frame)
	after: ((ok: boolean) -> ())?,
}

function commands.new(opts: any): any
	local core = opts.core
	local clock = opts.clock
	local presenter = opts.presenter
	local LuauUI = opts.LuauUI
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
			existing = core:signal("idle")
			statuses[id] = existing
		end
		return existing
	end

	local function reasonSignal(id: string): any
		local existing = reasons[id]
		if existing == nil then
			existing = core:signal("")
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
		return statusSignal(id):get() == "pending"
	end

	-- the toast a rejection owes the player. `key = id` so a retry SUPERSEDES
	-- its predecessor instead of stacking a second copy of the same sentence.
	local function toast(id: string, message: string)
		if presenter == nil or presenter.presentToast == nil or LuauUI == nil then
			return
		end
		local UI = LuauUI.UI
		presenter.presentToast(
			UI.ZStack({
				id = "CartwheelToast",
				canvasGroup = true,
				children = {
					UI.Box({
						id = "Plate",
						surface = "raised",
						width = { type = "fill", weight = 1 },
						height = { type = "content" },
					}),
					UI.Text({ id = "Body", text = message, textSize = "label", padding = "s" }),
				},
			}),
			{ key = id, position = "bottom", duration = 4 }
		)
	end

	local function emit(kind: string, id: string, reason: string?)
		if presenter ~= nil and presenter.emitFeedback ~= nil then
			presenter.emitFeedback({ type = kind, reason = reason, context = { command = id } })
		end
	end

	-- submit(spec) -> boolean started. A second submit for an id already in
	-- flight is refused (the control is disabled while pending, so this is the
	-- keyboard-repeat / double-tap case, not a legal verb).
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

	-- the deterministic diagnostic: every command this session ran, in order
	function self.dump(): any
		local out = {}
		for _, entry in log do
			table.insert(out, { id = entry.id, ok = entry.ok, reason = entry.reason })
		end
		return out
	end

	function self.dispose()
		for _, signal in statuses do
			signal:dispose()
		end
		for _, signal in reasons do
			signal:dispose()
		end
		statuses = {}
		reasons = {}
	end

	return self
end

return table.freeze(commands)
