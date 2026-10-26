--!strict
local Compose = require("../vendor/compose/core")
local Shared = require("./types")
local Controls = require("./control_types")
local Props = require("./hud_props")
local MediaProps = require("./media_props")
local reducedMotion = require("./motion").reduced

return function(ctx: Shared.Context, UI: Controls.Controls)
	local C, runtime = ctx.Compose, ctx.runtime
	UI.Typewriter = ctx.construct("Typewriter", function(spec: Props.TypewriterProps): TextLabel
		assert(spec.reveal == nil and spec.truncate ~= "middle", "Facet Typewriter requires the full text")
		assert(spec.MaxVisibleGraphemes == nil, "Facet Typewriter owns MaxVisibleGraphemes")
		local frames = assert(runtime.host.frames, "Facet Typewriter requires a runtime clock")
		local owner = assert(C.currentOwner())
		local revealed = C.cell(false)
		local fields = table.clone((spec :: unknown) :: { [string]: unknown })
		for _, key in { "onRevealed", "controls", "ref" } do
			fields[key] = nil
		end
		fields.MaxVisibleGraphemes = 0
		local label = UI.Text((fields :: unknown) :: MediaProps.TextProps) :: TextLabel
		local content = ctx.observe.ContentText(label)
		local painted = ctx.observe.Text(label)
		local reduce = reducedMotion(ctx)
		local function finish()
			if Compose.owner.isDisposed(owner) or revealed:peek() then
				return
			end
			label.MaxVisibleGraphemes = -1
			revealed:set(true)
			if spec.onRevealed then
				C.withOwner(owner, spec.onRevealed)
			end
		end
		if spec.controls then
			spec.controls.revealed, spec.controls.finish = revealed, finish
			C.cleanup(function()
				if spec.controls then
					spec.controls.revealed, spec.controls.finish = nil, nil
				end
			end)
		end
		local previousText: string? = nil
		local previousContent: string? = nil
		local started = frames.now()
		C.watch(function(use: Shared.Use)
			local raw = use(painted)
			local line = use(content)
			local reduced = reduce(use)
			local interval = ctx.metric("motion.typewriter.grapheme", use)
			local pause = ctx.metric("motion.typewriter.pause", use)
			assert(
				interval > 0 and pause >= 0,
				"Facet Typewriter timing requires a positive interval and nonnegative pause"
			)
			if raw ~= previousText or line ~= previousContent then
				previousText, previousContent = raw, line
				started = frames.now() + pause
				revealed:set(false)
				label.MaxVisibleGraphemes = 0
			elseif revealed:peek() then
				return
			end
			if reduced then
				finish()
				return
			end
			runtime.scheduler().after(0, function()
				if revealed:peek() then
					return
				end
				local total = 0
				for _ in utf8.graphemes(line) do
					total += 1
				end
				local clock = runtime.clock { start = started }
				C.watch(function(read: Shared.Use)
					if read(revealed) then
						return
					end
					local visible = math.min(total, math.floor(read(clock) / interval))
					if visible >= total then
						finish()
					else
						label.MaxVisibleGraphemes = visible
					end
				end)
			end)
		end)
		return label
	end)
end
