--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Context = {
	Facet: typeof(require("@repo/src")),
	mount: (
		(FacetControls, RobloxHost, ComposeModule, { runtime: ComposeRuntime }) -> GuiObject,
		{ size: Vector2, frames: number, motionLevel: string }
	) -> Instance,
	settle: (number?) -> (),
	check: (string, boolean, unknown?) -> (),
	attach: (string, unknown) -> (),
}
type Sample = {
	time: number,
	x: number,
	y: number,
	width: number,
	height: number,
	transparency: number,
	visible: boolean,
	currentTransparency: number,
	targetX: number,
	sliding: boolean,
}

return {
	{
		id = "selection-has-one-continuous-motion",
		contracts = {},
		run = function(t: Context)
			local choose: ((string) -> ())? = nil
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
				local selected = Compose.cell("a")
				choose = function(value: string)
					selected:set(value)
				end
				local sheet = t.Facet.themes.createStyleSheet(env.runtime, nil, { motionLevel = "normal" })
				return Host.Frame "Motion" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					sheet,
					Host.StyleLink { StyleSheet = Compose.static(sheet) },
					UI.Picker "MotionPicker" {
						style = "segmented",
						selected = selected,
						Size = UDim2.fromOffset(360, 48),
						options = {
							{ value = "a", label = "One" },
							{ value = "b", label = "Two" },
							{ value = "c", label = "Three" },
						},
					},
				}
			end, { size = Vector2.new(600, 300), frames = 60, motionLevel = "normal" })
			local fill = assert(stage:FindFirstChild("SelectionFill", true)) :: Frame
			local track: GuiObject? = nil
			for _, node in stage:GetDescendants() do
				if node:IsA("GuiObject") and node:HasTag("facet-segmented") then
					track = node
				end
			end
			local strip = assert(track)
			for _, value in { "b", "c", "a" } do
				local frames: { Sample } = {}
				local started = os.clock()
				assert(choose)(value)
				repeat
					t.settle(1)
					task.defer(coroutine.running())
					coroutine.yield()
					local current: GuiObject? = nil
					for _, node in strip:GetDescendants() do
						if node:IsA("GuiObject") and node:HasTag("facet-segment-current") then
							current = node
						end
					end
					local position, size = fill.AbsolutePosition - strip.AbsolutePosition, fill.AbsoluteSize
					table.insert(frames, {
						time = os.clock() - started,
						x = position.X,
						y = position.Y,
						width = size.X,
						height = size.Y,
						transparency = fill:GetStyled("BackgroundTransparency") :: number,
						visible = fill:GetStyled("Visible") :: boolean,
						currentTransparency = assert(current):GetStyled("BackgroundTransparency") :: number,
						targetX = assert(current).AbsolutePosition.X - strip.AbsolutePosition.X,
						sliding = strip:HasTag("facet-segmented-slides"),
					})
				until os.clock() - started >= 2
				t.attach("frames-" .. value .. ".json", frames)
				local direction = if value == "a" then -1 else 1
				local reversals, gaps, moving, departures = 0, 0, 0, 0
				local final = frames[#frames]
				local arrived = false
				for index, frame in frames do
					if index > 1 and frame.visible and frames[index - 1].visible then
						local delta = direction * (frame.x - frames[index - 1].x)
						reversals += if delta < -0.5 then 1 else 0
						moving += if delta > 0.5 then 1 else 0
					end
					if frame.visible then
						local distance = math.max(
							math.abs(frame.x - final.x),
							math.abs(frame.y - final.y),
							math.abs(frame.width - final.width),
							math.abs(frame.height - final.height)
						)
						departures += if arrived and distance > 0.5 then 1 else 0
						arrived = arrived or distance <= 0.5
					end
					local transparency = if frame.visible then frame.transparency else frame.currentTransparency
					gaps += if transparency > 0.01 then 1 else 0
				end
				t.check(value .. " moves across rendered frames", moving > 1, moving)
				t.check(value .. " moves monotonically", reversals == 0, reversals)
				t.check(value .. " finishes at the selected segment", final.x == math.floor(final.targetX), final)
				t.check(value .. " stays at the destination after arriving", arrived and departures == 0, departures)
				t.check(value .. " hands off without a second fade", gaps == 0, gaps)
			end
		end,
	},
}
