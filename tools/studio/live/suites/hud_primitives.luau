--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type TimerControls = typeof(require("@repo/tools/typecheck/aliases").TimerControls)
type TypewriterControls = typeof(require("@repo/tools/typecheck/aliases").TypewriterControls)
type Live = {
	mount: (
		(Controls, Host, Compose) -> Instance,
		{ frames: number, motionLevel: string, size: Vector2 }?
	) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
}
local RunService = game:GetService("RunService")

local function verify(t: Live, width: number, motion: string)
	local label: TextLabel
	local timer: TextLabel
	local reveal: TypewriterControls = {}
	local clock: TimerControls = {}
	local revealed, completed = 0, 0
	local nextLine: () -> ()
	t.mount(function(UI: Controls, _Host: Host, C: Compose): Instance
		local line = C.cell("<b>e\u{301}&amp;\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}</b>")
		nextLine = function()
			line:set("<i>Next line</i>")
		end
		label = UI.Typewriter "Dialogue" {
			text = line,
			rich = true,
			wrap = true,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			controls = reveal,
			onRevealed = function()
				revealed += 1
			end,
		}
		timer = UI.Timer "Deadline" {
			deadline = os.clock() + 1,
			now = os.clock,
			controls = clock,
			onComplete = function()
				completed += 1
			end,
		}
		return UI.VStack "HudLive" { width = "fill", gap = "s", label, timer }
	end, { frames = 1, motionLevel = motion, size = Vector2.new(width, 300) })
	local count = 0
	for _ in utf8.graphemes(label.ContentText) do
		count += 1
	end
	t.check(
		"engine removes tags and decodes entities",
		label.ContentText == "e\u{301}&\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
		label.ContentText
	)
	t.check("engine counts composed graphemes", count == 3, count)
	local sawPartial = false
	local untilTime = os.clock() + 3
	repeat
		sawPartial = sawPartial or label.MaxVisibleGraphemes > 0 and label.MaxVisibleGraphemes < count
		RunService.Heartbeat:Wait()
	until assert(reveal.revealed):peek() and assert(clock.completed):peek() or os.clock() > untilTime
	t.check("line completes once", revealed == 1 and label.MaxVisibleGraphemes == -1, revealed)
	t.check("deadline completes once", completed == 1 and timer.Text == "0:00", completed)
	t.check("normal motion reveals partial text", motion ~= "normal" or sawPartial)
	t.check("text fits the compact or wide label", label.TextFits, label.TextBounds)
	nextLine()
	if motion == "normal" then
		t.check("new line restarts", label.MaxVisibleGraphemes == 0)
	end
	assert(reveal.finish)()
	assert(reveal.finish)()
	t.check("skip completes the line once", revealed == 2 and label.MaxVisibleGraphemes == -1, revealed)
end

return {
	{
		id = "wide-normal",
		contracts = { "UI.Timer", "UI.Typewriter" },
		run = function(t: Live)
			verify(t, 900, "normal")
		end,
	},
	{
		id = "compact-normal",
		contracts = { "UI.Timer", "UI.Typewriter" },
		run = function(t: Live)
			verify(t, 320, "normal")
		end,
	},
	{
		id = "compact-limited",
		contracts = { "UI.Timer", "UI.Typewriter" },
		run = function(t: Live)
			verify(t, 320, "limited")
		end,
	},
	{
		id = "compact-none",
		contracts = { "UI.Timer", "UI.Typewriter" },
		run = function(t: Live)
			verify(t, 320, "none")
		end,
	},
}
