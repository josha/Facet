--!strict
-- Glade (RA-P1) — the small shared pieces every surface reuses: chips, section
-- headings, the purchase-command button, and the rejection notice.
--
-- SPEC VOCABULARY RECONCILIATION, stated once here because it is the same in
-- every file: the spec names PALETTE roles ("Box surface = surfaceStrong"), while
-- `surface` is the framework's eight-value SURFACE vocabulary. The mapping this
-- proof uses throughout is `surface -> "base"`, `surfaceStrong -> "raised"`, and
-- the two read-only Text surfaces ("chip", "badge") keep their own names.

local parts = {}

-- A read-only tag: "Low", "Empty", "Best value", "Lumen only", a price. Never
-- truncates by contract (spec §13) — `lineLimit = 1` with no `disclose` would
-- ellipsize, so these deliberately declare neither and are allowed to wrap.
function parts.chip(ctx: any, id: string, text: any): any
	return ctx.UI.Text({ id = id, text = text, surface = "chip", textSize = "caption" })
end

function parts.heading(ctx: any, id: string, text: any): any
	return ctx.UI.Text({ id = id, text = text, textSize = "heading" })
end

function parts.body(ctx: any, id: string, text: any): any
	return ctx.UI.Text({ id = id, text = text, textSize = "body", role = "secondary" })
end

function parts.caption(ctx: any, id: string, text: any): any
	return ctx.UI.Text({ id = id, text = text, textSize = "caption", role = "secondary" })
end

-- THE PURCHASE-COMMAND BUTTON (spec §9's lifecycle table), used by every
-- purchase-shaped verb in the proof: pack buys, charm tiers, and the keeper's
-- restore. One control, four phases, and PENDING NEVER READS AS SUCCESS — it is
-- disabled and it says "Confirming…" while the command is in flight.
--
-- IT DECLARES NO `compactLabel`, AND THAT IS THE POINT (found by the suite,
-- 2026-08-08). `compactLabel` is construction-only by contract — a compact
-- representation is what a control HAS, not a state it passes through — while
-- this button's label is the phase. Declaring the idle compact form ("Buy",
-- "Shop") meant the framework's own ladder drew THAT word the moment the label
-- grew to "Confirming…" and stopped fitting: a pending purchase rendered as an
-- offer to buy again, which is precisely the invariant this table exists to
-- defend. With no compact form the long phase ellipsizes instead, and an
-- ellipsized "Confirming…" still reads as confirming. Recorded as a framework
-- finding: a phase-bearing control has no way to declare a compact form per
-- phase, and a per-phase `When` would move focus mid-command.
export type CommandSpec = {
	id: string,
	commandId: string,
	label: any, -- Readable<string> | string: the idle label
	role: string?,
	onActivate: () -> (),
}

function parts.commandButton(ctx: any, spec: CommandSpec): any
	local core = ctx.core
	local status = ctx.commerce.status(spec.commandId)
	local label = core:memo(function(use)
		if use(status) == "pending" then
			return ctx.Lnow("picker.pending")
		end
		if ctx.Facet.UI.isReadable(spec.label) then
			return use(spec.label)
		end
		return spec.label
	end)
	local enabled = core:memo(function(use)
		return use(status) ~= "pending"
	end)
	ctx.scope:own(label)
	ctx.scope:own(enabled)
	return ctx.UI.Button({
		id = spec.id,
		label = label,
		enabled = enabled,
		role = spec.role,
		onActivate = spec.onActivate,
	})
end

-- THE REJECTION NOTICE (spec §9). It appears directly under the control that was
-- pressed, carries the player-facing reason copy, and clears on the next attempt
-- or when the surface is dismissed. Nothing is silent and nothing reverts
-- invisibly.
function parts.rejectionNotice(ctx: any, id: string, commandId: string): any
	local core = ctx.core
	local status = ctx.commerce.status(commandId)
	local reason = ctx.commerce.reason(commandId)
	local rejected = core:memo(function(use)
		return use(status) == "rejected"
	end)
	local copy = core:memo(function(use)
		local why = use(reason)
		return ctx.Lnow("reject." .. (why or "fallback"))
	end)
	ctx.scope:own(rejected)
	ctx.scope:own(copy)
	return ctx.UI.When({
		id = id,
		condition = rejected,
		transition = { enter = "slide-down", fade = true, class = "container" },
		thenView = function()
			return ctx.UI.ZStack({
				id = "Notice",
				canvasGroup = true,
				width = { type = "fill", weight = 1 },
				children = {
					ctx.UI.stroke(
						ctx.UI.VStack({
							id = "Plate",
							surface = "raised",
							padding = "s",
							width = { type = "fill", weight = 1 },
							children = { ctx.UI.Text({ id = "Why", text = copy, textSize = "body" }) },
						}),
						{}
					),
				},
			})
		end,
	})
end

-- A round well behind a piece of scene art. The proof's one avatar/jar treatment,
-- reused for nectar jars, wisp portraits and flora cards (spec §10: "the one
-- avatar treatment reused everywhere").
function parts.well(ctx: any, id: string, art: { number }, size: number, children: { any }?): any
	local kids: { any } = {
		ctx.UI.corners(
			ctx.UI.Box({
				id = "Fill",
				tint = ctx.tint(art),
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
			}),
			"pill"
		),
	}
	if children ~= nil then
		for _, child in children do
			table.insert(kids, child)
		end
	end
	return ctx.UI.corners(
		ctx.UI.ZStack({
			id = id,
			surface = "raised",
			width = { type = "fixed", px = size },
			height = { type = "fixed", px = size },
			children = kids,
		}),
		"pill"
	)
end

return parts
