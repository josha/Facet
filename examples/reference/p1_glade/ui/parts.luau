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
	local CommandButton = ctx.Facet.component(function(ui)
		local status = ui.read(ctx.commerce.status(spec.commandId))
		local locale = ui.read(ctx.state.locale)
		local idle = if ctx.Facet.UI.isReadable(spec.label) then ui.read(spec.label) else spec.label
		return ctx.Facet.View.Button({
			id = spec.id,
			label = function()
				locale()
				if status() == "pending" then
					return ctx.Lnow("picker.pending")
				end
				return if type(idle) == "function" then idle() else idle
			end,
			enabled = function()
				return status() ~= "pending"
			end,
			role = spec.role,
			onActivate = spec.onActivate,
		})
	end)
	return CommandButton({})
end

-- This branch owns its notice; rejected state remains in the shared model.
function parts.rejectionNotice(ctx: any, id: string, commandId: string): any
	local Notice = ctx.Facet.component(function(ui)
		local UI = ctx.Facet.View
		local status, reason = ui.read(ctx.commerce.status(commandId)), ui.read(ctx.commerce.reason(commandId))
		local locale = ui.read(ctx.state.locale)
		return UI.When({
			id = id,
			condition = function()
				return status() == "rejected"
			end,
			transition = { enter = "slide-down", fade = true, class = "container" },
			UI.ZStack({
				id = "Notice",
				canvasGroup = true,
				width = UI.fill(),
				UI.stroke(
					UI.VStack({
						id = "Plate",
						surface = "raised",
						padding = "s",
						width = UI.fill(),
						UI.Text({
							id = "Why",
							textSize = "body",
							text = function()
								locale()
								return ctx.Lnow("reject." .. (reason() or "fallback"))
							end,
						}),
					}),
					{}
				),
			}),
		})
	end)
	return Notice({})
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
				width = ctx.UI.fill(),
				height = ctx.UI.fill(),
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
