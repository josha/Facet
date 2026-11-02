--!strict

type TextPropsText = typeof(require("@repo/tools/typecheck/aliases").TextPropsText)
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
local rules = require("@self/rules")
local terminal = { rules = rules, CANVAS = { w = 640, h = 480 }, TITLE = "OUTPOST 7 — POWER" }

type ExampleContext = typeof(require("@repo/examples/types").Context)
type Allocation = rules.Allocation
type Verdict = rules.Verdict
type Outcome = Verdict
type Reply = { revision: number?, allocation: Allocation?, code: string?, message: string? }
type Envelope = {
	requestId: number,
	expectedRevision: number,
	payload: { kind: string, allocation: Allocation },
}
type Snapshot = {
	phase: string,
	status: string,
	draft: Allocation,
	outpost: Allocation,
	revision: number,
	verdict: Verdict,
	canApply: boolean,
	complete: boolean,
	message: string?,
	outcome: Outcome?,
	exitReason: string?,
	counters: { sent: number, refusedLocally: number, applied: number },
}
type Options = { onState: ((Snapshot) -> ())?, send: ((Envelope) -> ...unknown)?, onExit: (() -> ())? }
function terminal.build(ctx: ExampleContext, options: Options?)
	local o: Options = options or {}
	local Compose, Host, UI = ctx.Compose, ctx.Host, ctx.UI
	local UDim, UDim2, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local confirmed = Compose.cell(rules.copy(rules.START))
	local revision = Compose.cell(0)
	local phase, status = Compose.cell("idle"), Compose.cell("idle")
	local noOutcome: Outcome? = nil
	local noReason: string? = nil
	local outcome: Value<Outcome?> = Compose.cell(noOutcome)
	local exitReason: Value<string?> = Compose.cell(noReason)
	local draft: { [string]: typeof(Compose.cell(0)) } = {}
	for _, consumer in rules.CONSUMERS do
		draft[consumer.id] = Compose.cell(rules.START[consumer.id])
	end
	local pendingId: number? = nil
	local sequence = 0
	local sent, refusedLocally, applied = 0, 0, 0
	local steps = {}
	local function allocation(use: Use?)
		local result: Allocation = {}
		for _, consumer in rules.CONSUMERS do
			result[consumer.id] = if use then use(draft[consumer.id]) else draft[consumer.id]:peek()
		end
		return result
	end
	local function seed(values: Allocation)
		ctx.runtime:batch(function()
			for _, consumer in rules.CONSUMERS do
				draft[consumer.id]:set(values[consumer.id])
			end
		end)
	end
	local verdict = Compose.formula(function(use: Use)
		return rules.validate(allocation(use))
	end)
	local canApply = Compose.formula(function(use: Use)
		return use(phase) == "engaged" and use(status) ~= "pending" and use(verdict).ok
	end)
	local message = Compose.formula(function(use: Use): string
		if use(status) == "pending" then
			return "Sending to the outpost…"
		end
		local result = use(outcome)
		return (if result then result.message else if use(verdict).ok then rules.OBJECTIVE else use(verdict).message)
			or ""
	end)
	function steps.snapshot(): Snapshot
		return {
			phase = phase:peek(),
			status = status:peek(),
			draft = allocation(),
			outpost = rules.copy(confirmed:peek()),
			revision = revision:peek(),
			verdict = verdict:peek(),
			canApply = canApply:peek(),
			complete = rules.allRunning(confirmed:peek()),
			message = message:peek(),
			outcome = outcome:peek(),
			exitReason = exitReason:peek(),
			counters = { sent = sent, refusedLocally = refusedLocally, applied = applied },
		}
	end
	local function publish()
		if o.onState then
			o.onState(steps.snapshot())
		end
	end
	function steps.ingest(nextRevision: number, values: Allocation)
		if nextRevision <= revision:peek() then
			return false
		end
		assert(rules.validate(values).ok, "Invalid authoritative allocation")
		ctx.runtime:batch(function()
			revision:set(nextRevision)
			confirmed:set(rules.copy(values))
		end)
		publish()
		return true
	end
	function steps.engage(values: Allocation?, nextRevision: number?)
		if values then
			if nextRevision == nil or nextRevision >= revision:peek() then
				confirmed:set(rules.copy(values))
				if nextRevision then
					revision:set(nextRevision)
				end
			end
		end
		pendingId = nil
		ctx.runtime:batch(function()
			phase:set("engaged")
			status:set("idle")
			outcome:set(nil)
			exitReason:set(nil)
			seed(confirmed:peek())
		end)
		publish()
		return steps.snapshot()
	end
	function steps.setValue(
		id: string,
		value: number
	): { ok: boolean, message: string?, reason: string?, value: number? }
		local consumer = rules.consumer(id)
		if not consumer then
			return { ok = false, message = rules.refusal("unknown", { id = id }) }
		end
		if status:peek() == "pending" then
			return { ok = false, reason = "pending" }
		end
		ctx.runtime:batch(function()
			outcome:set(nil)
			draft[id]:set(math.clamp(math.floor(value), 0, consumer.capacity))
		end)
		publish()
		return { ok = true, value = draft[id]:peek() }
	end
	function steps.adjust(id: string, delta: number)
		return steps.setValue(id, (if draft[id] then draft[id]:peek() else 0) + delta)
	end
	function steps.apply(): { sent: boolean, reason: string?, requestId: number?, allocation: Allocation? }
		if phase:peek() ~= "engaged" then
			return { sent = false, reason = phase:peek() }
		end
		if pendingId then
			return { sent = false, reason = "pending" }
		end
		local values = allocation()
		local valid = rules.validate(values)
		if not valid.ok then
			refusedLocally += 1
			outcome:set(valid)
			publish()
			return { sent = false, reason = valid.code }
		end
		if not o.send then
			ctx.runtime:batch(function()
				status:set("rejected")
				outcome:set({ ok = false, code = "session", message = rules.refusal("session") })
			end)
			publish()
			return { sent = false, reason = "no-transport" }
		end
		sequence += 1
		pendingId = sequence
		sent += 1
		ctx.runtime:batch(function()
			status:set("pending")
			outcome:set(nil)
		end)
		local requestId = sequence
		local delivered, failure = pcall(o.send, {
			requestId = requestId,
			expectedRevision = revision:peek(),
			payload = { kind = "set", allocation = values },
		})
		if not delivered then
			pendingId = nil
			status:set("rejected")
			outcome:set({
				ok = false,
				code = "transport",
				message = "The command could not be sent. Try again.",
				detail = tostring(failure),
			})
			publish()
			return { sent = false, reason = "transport", requestId = requestId }
		end
		publish()
		return { sent = true, requestId = requestId, allocation = values }
	end
	function steps.reset(): { sent: boolean, reason: string?, requestId: number?, allocation: Allocation? }
		if pendingId then
			return { sent = false, reason = "pending" }
		end
		seed(rules.START)
		return steps.apply()
	end
	function steps.confirm(requestId: number?, result: Reply?)
		if requestId ~= pendingId or pendingId == nil then
			return false
		end
		local before = confirmed:peek()
		pendingId = nil
		if result and result.allocation then
			steps.ingest(result.revision or revision:peek() + 1, result.allocation)
		end
		applied += 1
		ctx.runtime:batch(function()
			status:set("confirmed")
			outcome:set({ ok = true, code = "applied", message = rules.outcomeLine(before, confirmed:peek()) })
		end)
		publish()
		return true
	end
	function steps.reject(requestId: number?, result: Reply?)
		if requestId ~= pendingId or pendingId == nil then
			return false
		end
		pendingId = nil
		ctx.runtime:batch(function()
			status:set("rejected")
			outcome:set({
				ok = false,
				code = result and result.code,
				message = result and result.message or rules.refusal("session"),
			})
		end)
		publish()
		return true
	end
	function steps.exit(reason: string?)
		if phase:peek() == "exited" then
			return false
		end
		pendingId = nil
		ctx.runtime:batch(function()
			phase:set("exited")
			status:set("idle")
			exitReason:set(reason or "exit-control")
		end)
		publish()
		if o.onExit then
			o.onExit()
		end
		return true
	end
	local function label(name: string, text: TextPropsText, height: number, size: number?)
		return UI.Text {
			Name = name,
			text = text,
			TextSize = size or 16,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, height),
			AutomaticSize = Enum.AutomaticSize.Y,
		}
	end
	local function screen()
		local rows: { Instance } = {}
		for index, consumer in rules.CONSUMERS do
			table.insert(
				rows,
				Host.Frame(consumer.id)({
					LayoutOrder = index,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 64),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.Frame "Copy" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -184, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) },
						label("Title", `{consumer.label} — needs {consumer.needs}`, 24),
						label("State", function(use: Use)
							local live = rules.isRunning(use(confirmed), consumer.id)
							local nextRunning = use(draft[consumer.id]) >= consumer.needs
							return (if nextRunning then consumer.running else consumer.idle)
								.. (if live ~= nextRunning then " (on Apply)" else "")
						end, 36, 13),
					},
					UI.Stepper {
						Name = consumer.id .. "Step",
						Position = UDim2.new(1, -172, 0, 8),
						Size = UDim2.fromOffset(172, 44),
						value = draft[consumer.id],
						min = 0,
						max = consumer.capacity,
						enabled = function(use: Use)
							return use(phase) == "engaged" and use(status) ~= "pending"
						end,
						onChange = function(value)
							steps.setValue(consumer.id, value)
						end,
					},
				})
			)
		end
		local root = Host.ScrollingFrame "OutpostTerminal" {
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 6,
			Host.UIPadding {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
			},
			Host.UIListLayout { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
			label("Title", terminal.TITLE, 30, 22),
			label("Budget", function(use: Use)
				local spent = rules.spent(allocation(use))
				return `{spent} of {rules.TOTAL} units allocated — {rules.TOTAL - spent} spare`
			end, 24),
			label("Confirmed", function(use: Use)
				return `Outpost: {rules.runningCount(use(confirmed))} of {#rules.CONSUMERS} consumers running.`
			end, 24, 13),
			Host.Frame "Consumers" {
				LayoutOrder = 4,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 200),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder },
				table.unpack(rows),
			},
			label("Message", message, 44),
			Host.Frame "Actions" {
				LayoutOrder = 6,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 44),
				Host.UIListLayout {
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 8),
				},
				UI.Button "Apply" {
					LayoutOrder = 1,
					label = "Apply",
					enabled = canApply,
					Size = UDim2.new(1 / 3, -6, 1, 0),
					onActivate = function()
						steps.apply()
					end,
				},
				UI.Button "Reset" {
					LayoutOrder = 2,
					label = "Reset",
					enabled = function(use: Use)
						return use(phase) == "engaged" and use(status) ~= "pending"
					end,
					Size = UDim2.new(1 / 3, -6, 1, 0),
					onActivate = function()
						steps.reset()
					end,
				},
				UI.Button "Exit" {
					LayoutOrder = 3,
					label = "Exit",
					role = "cancel",
					Size = UDim2.new(1 / 3, -6, 1, 0),
					onActivate = function()
						steps.exit("exit-control")
					end,
				},
			},
		}
		root:AddTag("facet-surface")
		return root
	end
	publish()
	return {
		screen = screen,
		steps = steps,
		report = steps.snapshot,
		model = { confirmed = confirmed, revision = revision, draft = draft, phase = phase, status = status },
	}
end
return terminal
