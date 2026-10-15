--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Roblox = require("../src/vendor/compose/roblox")
local Shared = require("../src/ui/types")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:case("typewriter uses native content graphemes theme timing skip and reduced motion", function(t)
		local register: unknown = require("../src/ui/typewriter")
		local environment = getfenv(register :: () -> ())
		local original = environment.utf8
		local counts: { [string]: number } =
			{ ["A&B"] = 3, Go = 2, ["e\u{301}!"] = 2, Next = 4, Last = 4, Unfinished = 10 }
		environment.utf8 = {
			graphemes = function(line: string): () -> number?
				local count = assert(counts[line], `missing native grapheme fixture: {line}`)
				local index = 0
				return function(): number?
					index += 1
					return if index <= count then index else nil
				end
			end,
		}
		t:defer(function()
			environment.utf8 = original
		end)
		local native = engineLib.new()
		local now = 0
		native.clock = function(): number
			return now
		end
		local function step(seconds: number)
			now += seconds
			native.heartbeat:Fire(seconds)
		end
		local runtime = Facet.Roblox.createRuntime((native :: unknown) :: Roblox.Engine)
		local C = Facet.Compose
		local text = C.cell("<b>A&amp;B</b>")
		local motion = C.cell("normal" :: Shared.MotionLevel)
		local theme = Facet.themes.neutralPackage()
		theme.metrics.motion.typewriter = { grapheme = 0.25, pause = 0.5 }
		local content: { [string]: string } = {
			["<b>A&amp;B</b>"] = "A&B",
			["<i>Go</i>"] = "Go",
			["e\u{301}!"] = "e\u{301}!",
			["Next"] = "Next",
			["Last"] = "Last",
		}
		native.onWrite(function(object, key, value)
			if key == "Text" and type(value) == "string" then
				local fields = (object :: unknown) :: { [string]: unknown }
				fields.ContentText = content[value] or value
			end
		end)
		local controls: Facet.TypewriterControls = {}
		local label: TextLabel
		local calls = 0
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, theme = theme, motionLevel = motion })
			label = UI.Typewriter "Dialogue" {
				text = text,
				rich = true,
				controls = controls,
				onRevealed = function()
					calls += 1
				end,
			}
			return label
		end, native.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local revealed, finish = assert(controls.revealed), assert(controls.finish)
		t:expect(label.Text):toBe("<b>A&amp;B</b>")
		t:expect(label.MaxVisibleGraphemes):toBe(0)
		t:expect(label:HasTag("facet-type-body")):toBe(true)
		step(0.5)
		t:expect(label.MaxVisibleGraphemes):toBe(0)
		step(0.25)
		t:expect(label.MaxVisibleGraphemes):toBe(1)
		step(0.25)
		t:expect(label.MaxVisibleGraphemes):toBe(2)
		step(0.25)
		t:expect(label.MaxVisibleGraphemes):toBe(-1)
		t:expect(revealed:peek()):toBe(true)
		t:expect(calls):toBe(1)
		finish()
		t:expect(calls):toBe(1)
		text:set("<i>Go</i>")
		t:expect(label.MaxVisibleGraphemes):toBe(0)
		t:expect(revealed:peek()):toBe(false)
		step(0.75)
		t:expect(label.MaxVisibleGraphemes):toBe(1)
		finish()
		t:expect(label.MaxVisibleGraphemes):toBe(-1)
		t:expect(calls):toBe(2)
		step(5)
		t:expect(calls):toBe(2)
		text:set("e\u{301}!")
		step(0.75)
		t:expect(label.MaxVisibleGraphemes):toBe(1)
		step(0.25)
		t:expect(revealed:peek()):toBe(true)
		text:set("Next")
		motion:set("limited")
		t:expect(label.MaxVisibleGraphemes):toBe(-1)
		t:expect(calls):toBe(4)
		motion:set("none")
		t:expect(calls):toBe(4)
		text:set("Last")
		t:expect(label.MaxVisibleGraphemes):toBe(-1)
		t:expect(calls):toBe(5)
		motion:set("normal")
		text:set("Unfinished")
		stop()
		t:expect(controls.finish):toBe(nil)
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
		step(20)
		finish()
		t:expect(calls):toBe(5)
	end)
end
