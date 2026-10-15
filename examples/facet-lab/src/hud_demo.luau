--!strict
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Context = {
	UI: typeof(require("@repo/tools/typecheck/aliases").FacetControls),
	Compose: typeof(require("@repo/tools/typecheck/aliases").ComposeModule),
	Facet: typeof(require("@repo/tools/typecheck/aliases").FacetModule),
}

local demo = {}

function demo.counters(c: Context): Instance
	local UI, C, format = c.UI, c.Compose, c.Facet.format
	local coins = C.cell(93210)
	return UI.VStack "HudCounters" {
		gap = "s",
		UI.HStack "CurrencyStrip" {
			gap = "m",
			UI.Text {
				text = function(use: Use): string
					return `Coins {format.compact(use(coins))}`
				end,
				textRole = "numeral",
			},
			UI.Text { text = `Gems {format.compact(2350)}`, textRole = "numeral" },
			UI.Text { text = `XP {format.compact(1250000)}`, textRole = "numeral" },
		},
		UI.Text {
			text = function(use: Use): string
				return `Wallet: {format.grouped(use(coins))} coins`
			end,
		},
		UI.Button {
			label = "Collect 500 coins",
			onActivate = function()
				coins:set(coins:peek() + 500)
			end,
		},
	}
end

function demo.timer(c: Context, hours: boolean, elapsed: boolean): Instance
	local UI, C = c.UI, c.Compose
	local deadline = C.cell(os.clock() + 8)
	local status = C.cell("Round in progress")
	local start = C.cell(os.clock())
	local controls: typeof(require("@repo/tools/typecheck/aliases").TimerControls) = {}
	local timer = UI.Timer "RoundDeadline" {
		deadline = if elapsed then nil else deadline,
		start = if elapsed then start else nil,
		now = os.clock,
		hours = hours,
		controls = controls,
		textRole = "numeral",
		onComplete = function()
			status:set("Round complete")
		end,
	}
	return UI.VStack "RoundTimer" {
		gap = "s",
		UI.Text { text = if elapsed then "Round elapsed" else "Time remaining", textRole = "label" },
		timer,
		UI.Text {
			text = function(use: Use): string
				return if use(assert(controls.completed)) then "Deadline reached" else "Clock running"
			end,
		},
		UI.Text { text = status },
		UI.Button {
			label = "Start round",
			onActivate = function()
				status:set("Round in progress")
				deadline:set(os.clock() + 8)
				start:set(os.clock())
			end,
		},
	}
end

function demo.dialogue(c: Context): Instance
	local UI, C = c.UI, c.Compose
	local line = C.cell("<b>Guide:</b> The gate is open. Follow the lights to the next camp.")
	local controls: typeof(require("@repo/tools/typecheck/aliases").TypewriterControls) = {}
	local status = C.cell("Guide is speaking")
	return UI.VStack "NpcDialogue" {
		gap = "s",
		UI.Typewriter "NpcLine" {
			text = line,
			rich = true,
			wrap = true,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			controls = controls,
			onRevealed = function()
				status:set("Line complete")
			end,
		},
		UI.Text { text = status, role = "secondary" },
		UI.HStack "DialogueActions" {
			gap = "s",
			UI.Button {
				label = "Skip",
				onActivate = function()
					if controls.finish then
						controls.finish()
					end
				end,
			},
			UI.Button {
				label = "Next line",
				onActivate = function()
					status:set("Guide is speaking")
					line:set(
						if line:peek() == "<b>Guide:</b> Stay close. The bridge is narrow."
							then "<b>Guide:</b> The gate is open. Follow the lights to the next camp."
							else "<b>Guide:</b> Stay close. The bridge is narrow."
					)
				end,
			},
		},
	}
end

return demo
