--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Sequence = typeof(require("@repo/tools/typecheck/aliases").Sequence)
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type Live = {
	mount: ((Controls, Host, Compose) -> Instance, { size: Vector2, frames: number, motionLevel: string }) -> GuiObject,
	settle: (number?) -> (),
	check: (string, boolean, unknown?) -> (),
}

return {
	{
		id = "shake-faces-preserve-native-layout",
		contracts = { "UI.shake" },
		run = function(t: Live)
			local faces: { GuiObject } = {}
			local slots: { GuiObject } = {}
			local effect: Sequence
			t.mount(function(UI: Controls, Host: Host): Instance
				for index = 1, 3 do
					local face = UI.Text {
						text = tostring(index),
						Size = UDim2.fromScale(1, 1),
						Rotation = index,
						BackgroundTransparency = 0,
					}
					faces[index] = face
					local props: FrameProps = {
						Size = UDim2.fromOffset(60, 60),
						BackgroundTransparency = 1,
						face,
					}
					slots[index] = Host.Frame(props)
				end
				effect = UI.shake(faces)
				local props: StackProps = { gap = "m", slots[1], slots[2], slots[3] }
				return UI.HStack(props)
			end, { size = Vector2.new(600, 240), frames = 12, motionLevel = "normal" })
			local positions: { Vector2 } = {}
			for index, slot in slots do
				positions[index] = slot.AbsolutePosition
			end
			effect.play()
			local moved, synchronized, stable = false, true, true
			for _ = 1, 60 do
				t.settle(1)
				local offset = faces[1].Rotation - 1
				moved = moved or math.abs(offset) > 0.01
				for index, face in faces do
					synchronized = synchronized and math.abs(face.Rotation - index - offset) < 0.00001
					stable = stable and slots[index].AbsolutePosition == positions[index]
				end
			end
			t.check("faces move during the effect", moved)
			t.check("all faces use the same phase", synchronized)
			t.check("native layout slots remain fixed", stable)
			t.check("the effect completes", effect.completed:peek())
			for index, face in faces do
				t.check(`face {index} restores its rotation`, face.Rotation == index, face.Rotation)
			end
			effect.play()
			t.settle(1)
			effect.cancel()
			t.check("cancel restores the first face", faces[1].Rotation == 1)
			effect.play()
			t.settle(1)
			effect.play()
			t.check("replay starts at the original rotation", faces[1].Rotation == 1)
			effect.finish()
			t.check("finish restores the first face", faces[1].Rotation == 1)
		end,
	},
	{
		id = "shake-reduced-motion-has-no-native-transform-writes",
		contracts = { "UI.shake" },
		run = function(t: Live)
			local face: GuiObject
			local effect: Sequence
			t.mount(function(UI: Controls, Host: Host): Instance
				face = Host.Frame { Size = UDim2.fromOffset(60, 60), Rotation = 11 }
				local targets: { GuiObject } = {}
				targets[1] = face
				effect = UI.shake(targets)
				local props: FrameProps = { face }
				return Host.Frame(props)
			end, { size = Vector2.new(600, 240), frames = 12, motionLevel = "limited" })
			local writes = 0
			local connection = face:GetPropertyChangedSignal("Rotation"):Connect(function()
				writes += 1
			end)
			effect.play()
			t.settle(3)
			connection:Disconnect()
			t.check("limited motion completes without rotation changes", writes == 0 and face.Rotation == 11, writes)
			t.check("limited motion completes immediately", effect.completed:peek())
		end,
	},
}
