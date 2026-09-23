--!strict
--[[ THE TWO ENGINE VALUE CONSTRUCTORS `applyRect` NEEDS, AND NOTHING ELSE.

	`src/client/screen_target.luau` cannot be required under Lune — it reaches
	engine globals at LOAD time — which is why a large family of pins reads it as
	text instead. `src/client/screen_presentation.luau` is different: it touches
	`UDim2` and `Path2DControlPoint` only INSIDE functions, so the module loads
	fine and the only thing standing between a headless test and the LIVE
	`applyRect` is that `UDim2.fromOffset` does not exist outside Roblox.

	So this installs it. That is worth doing rather than mirroring `applyRect`
	into the fake target, because a mirror can agree with itself while the
	shipped code does something else — the exact failure `tests/lib/fake_target`'s
	own header and the SF-M9 handled-prop gate exist to prevent. A test that
	drives the real function cannot have that problem.

	WHAT IT IS NOT. It is not a Roblox emulator and must not grow into one. Two
	constructors, both pure value types with public arithmetic, both returning a
	plain table a test can read back. Nothing in `src/`, `tests/` or `tools/`
	feature-detects `UDim2` (checked), so defining it changes no other code path;
	`install()` is idempotent and leaves a real engine's own globals alone.

	IF A LATER TEST NEEDS A THIRD CONSTRUCTOR, add it here rather than inline, so
	the answer to "what does headless pretend to be" stays in one file.
]]

local gui_value_shim = {}

export type Offset = { x: number, y: number }

-- THROUGH `getfenv(0)`, AND NOT THROUGH `_G` — measured, because the obvious
-- spelling is the wrong one. Under Lune every module shares ONE global
-- environment, but `_G` is a DIFFERENT table from it: writing `_G.UDim2` leaves
-- `screen_presentation`'s own bare `UDim2` lookup nil and the shim silently does
-- nothing at all. Found the way these are always found — by the required module
-- erroring on the very line the shim was written to serve.
function gui_value_shim.install()
	local env: any = getfenv(0)
	if env.UDim2 == nil then
		env.UDim2 = {
			fromOffset = function(x: number, y: number): Offset
				return { x = x, y = y }
			end,
		}
	end
	if env.Vector2 == nil then
		env.Vector2 = {
			new = function(x: number, y: number)
				-- Match the engine's component names; retain the older test aliases.
				return { X = x, Y = y, x = x, y = y }
			end,
		}
	end
end

--[[ THE COLOUR VALUES THE ENGINE HAS AND LUNE DOES NOT (phase5 ColorPicker). A
	`Color3` is a caller's value, not a paint path, so a headless mount of a colour
	control must be born like the engine: Lune's own `@lune/roblox` Color3 (the same
	`fromRGB`/`fromHSV`/`ToHSV`/`R,G,B`), and a BrickColor whose `palette` takes the
	engine's 0..127 index (Lune's is 1-based; measured, evidence/phase5/probes.md).
	Nothing reads these globals at load except `tokens/chrome_props`, whose engine
	branch also needs `ColorSequence`, which stays absent. ]]
function gui_value_shim.installColor()
	local env: any = getfenv(0)
	if env.Color3 ~= nil then
		return
	end
	local roblox: any = require("@lune/roblox")
	env.Color3 = roblox.Color3
	env.BrickColor = {
		palette = function(index: number)
			if type(index) ~= "number" or index < 0 or index > 127 or index % 1 ~= 0 then
				error(`palette index out of bounds ({tostring(index)})`)
			end
			return roblox.BrickColor.palette(index + 1)
		end,
	}
end

return gui_value_shim
