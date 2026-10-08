--!strict
export type State = { view: GuiObject?, content: GuiObject? }
export type Driver = (unknown, State) -> ()
return function(
	step: (string) -> (),
	press: (unknown, { string }, number?) -> (),
	settle: (number) -> (),
	select: (GuiObject) -> ()
): { [string]: Driver }
	return {
		["zoom-gamepad"] = function(t, state)
			select(assert(state.view))
			press(t, { "ButtonR2" })
			settle(30)
			step("afterTrigger")
			press(t, { "Stick2Right" }, 30)
			step("afterStick")
			press(t, { "ButtonY" })
			settle(30)
			step("afterFit")
		end,
		["travel-gamepad"] = function(t, state)
			local root = assert(assert(state.content).Parent).Parent
			local send = assert(assert(root):FindFirstChild("Send", true)) :: GuiObject
			local back = assert(assert(root):FindFirstChild("Return", true)) :: GuiObject
			select(send)
			press(t, { "ButtonA" })
			settle(40)
			step("afterSend")
			select(back)
			press(t, { "ButtonA" })
			settle(40)
			step("afterReturn")
		end,
	}
end
