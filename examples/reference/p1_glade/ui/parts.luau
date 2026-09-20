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
	return ctx.UI.Text(id)({ text = text, surface = "chip", textSize = "caption" })
end

function parts.heading(ctx: any, id: string, text: any): any
	return ctx.UI.Text(id)({ text = text, textSize = "heading" })
end

function parts.body(ctx: any, id: string, text: any): any
	return ctx.UI.Text(id)({ text = text, textSize = "body", role = "secondary" })
end

function parts.caption(ctx: any, id: string, text: any): any
	return ctx.UI.Text(id)({ text = text, textSize = "caption", role = "secondary" })
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
	local function CommandButton(): any
		local status = (ctx.commerce.status(spec.commandId))
		local locale = ctx.state.locale
		local UI = ctx.UI
		local idle = spec.label
		return UI.Button(spec.id)({
			label = function(use)
				use(locale)
				if use(status) == "pending" then
					return ctx.Lnow("picker.pending")
				end
				return if ctx.Compose.isReadable(idle) then use(idle) else idle
			end,
			enabled = function(use)
				return use(status) ~= "pending"
			end,
			role = spec.role,
			onActivate = spec.onActivate,
		})
	end
	return CommandButton()
end

-- This branch owns its notice; rejected state remains in the shared model.
function parts.rejectionNotice(ctx: any, id: string, commandId: string): any
	local function Notice(): any
		local UI = ctx.UI
		local status, reason = (ctx.commerce.status(commandId)), (ctx.commerce.reason(commandId))
		local locale = ctx.state.locale
		return ctx.when(id)({
			condition = function(use)
				return use(status) == "rejected"
			end,
			thenView = function()
				return UI.ZStack("Notice")({
					canvasGroup = true,
					width = UI.fill(),
					UI.stroke(
						UI.VStack("Plate")({
							surface = "raised",
							padding = "s",
							width = UI.fill(),
							UI.Text("Why")({
								textSize = "body",
								text = function(use)
									use(locale)
									return ctx.Lnow("reject." .. (use(reason) or "fallback"))
								end,
							}),
						}),
						{}
					),
				})
			end,
		})
	end
	return Notice()
end

-- A round well behind a piece of scene art. The proof's one avatar/jar treatment,
-- reused for nectar jars, wisp portraits and flora cards (spec §10: "the one
-- avatar treatment reused everywhere").
function parts.well(ctx: any, id: string, art: { number }, size: number, children: { any }?): any
	local kids: { any } = {
		ctx.UI.corners(
			ctx.UI.Box("Fill")({
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
		ctx.UI.ZStack(id)(ctx.withChildren({
			surface = "raised",
			width = { type = "fixed", px = size },
			height = { type = "fixed", px = size },
		}, kids)),
		"pill"
	)
end

-- The surface's top bar: a Back verb, a one-line title, then trailing nodes.
function parts.navBar(ctx: any, spec: any): any
	local UI = ctx.UI
	local props: any = { gap = spec.gap or "s", align = "center", padding = spec.padding, width = UI.fill() }
	if spec.onBack ~= nil then
		table.insert(
			props,
			UI.Button("Back")({
				label = spec.backLabel,
				compactLabel = { icon = "chevron.leading", prefer = true },
				onActivate = spec.onBack,
			})
		)
	end
	if spec.title ~= nil then
		table.insert(
			props,
			UI.Text("Title")({
				text = spec.title,
				textSize = spec.titleSize or "title",
				lineLimit = 1,
				disclose = true,
				width = spec.titleWidth,
			})
		)
	end
	table.insert(props, UI.Spacer("Push")({}))
	for _, node in spec.trailing or {} do
		table.insert(props, node)
	end
	return UI.HStack(spec.id or "NavBar")(props)
end

return parts
