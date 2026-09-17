--!strict
-- The same named presets serve value motion, local paint, and coordinated layout.
local classes = require("./classes")
local curves = require("./curves")
local policy = {}
export type Spec = {
	layout: (string | boolean)?,
	scale: (string | boolean)?,
	opacity: (string | boolean)?,
	rotation: (string | boolean)?,
	offset: (string | boolean)?,
}
local keys = { layout = true, scale = true, opacity = true, rotation = true, offset = true }
function policy.check(value: any): (boolean, string?)
	if type(value) ~= "table" then
		return false, "an animation table"
	end
	for key, preset in value do
		if not keys[key] then
			return false, `unknown animation property '{tostring(key)}'`
		end
		if preset ~= false then
			if type(preset) ~= "string" then
				return false, `animation.{key} expects a named preset or false`
			end
			if not classes.isRegistered(preset) and not curves.isRegistered(preset) then
				return false, `unknown animation preset '{preset}'`
			end
		end
	end
	return true
end
function policy.value(clock: any, initial: number, preset: string): any
	return if curves.isRegistered(preset) then clock:tween(initial, preset) else clock:spring(initial, preset)
end
function policy.session(clock: any, preset: string): any
	return {
		newSpring = function()
			return policy.value(clock, 1, preset)
		end,
		carriesVelocity = not curves.isRegistered(preset),
	}
end
return policy
