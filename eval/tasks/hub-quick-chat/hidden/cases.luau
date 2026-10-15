--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local S = require("../../extended/hidden/support")
local cases: { Play.Case } = {
	{
		id = "quick-chat-open-send",
		tier = "spec",
		screen = "quick-chat",
		run = function(qa, context)
			if qa.device.id == "desktop" then
				local ok, detail = qa:press("Q")
				Check.that(context, ok, detail)
			else
				S.tap(qa, context, "Quick Chat")
			end
			for _, words in
				{ "Hello!", "Good luck!", "Nice race!", "Thanks!", "Follow me!", "Ready!", "Sorry!", "Well played!" }
			do
				S.target(qa, context, words)
			end
			S.capture(qa, context, "quick-chat")
			local before = Check.number(S.state(qa), "chatCount")
			S.back(qa, context, "Quick Chat")
			Check.that(context, Check.number(S.state(qa), "chatCount") == before, "cancel sends nothing")
			S.tap(qa, context, "Quick Chat")
			S.tap(qa, context, "Good luck!")
			Check.text(qa, context, "^good luck!$", "send shows message outside wheel")
			Check.that(context, Check.number(S.state(qa), "chatCount") == before + 1, "one message is sent")
		end,
	},
	{
		id = "quick-chat-cooldown",
		tier = "spec",
		screen = "chat-sent",
		run = function(qa, context)
			local before = Check.number(S.state(qa), "chatCount")
			S.tap(qa, context, "Quick Chat")
			Check.text(qa, context, "cooldown", "cooldown is visible")
			local choice = Check.visible(qa, context, { role = "button", exact = "thanks!" }, "message remains visible")
			Check.that(context, not choice.interactable, "cooldown disables send")
			Check.that(context, Check.number(S.state(qa), "chatCount") == before, "cooldown sends nothing")
			S.capture(qa, context, "chat-sent")
			qa:sleep(5.2)
			S.tap(qa, context, "Thanks!")
			Check.that(context, Check.number(S.state(qa), "chatCount") == before + 1, "send works after cooldown")
			S.tap(qa, context, "Quick Chat")
			S.back(qa, context, "Quick Chat")
		end,
	},
}
return cases
