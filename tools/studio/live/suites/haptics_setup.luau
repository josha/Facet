--!strict
return {
	{
		id = "haptics-mount-feedback-demo",
		contracts = { "risk:haptics" },
		run = function(t: any)
			local built
			local stage = t.mount(
				function(
					UI: typeof(require("@repo/src").controls(nil :: any)),
					Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
					Compose: typeof(require("@repo/src/vendor/compose/core")),
					env
				)
					built = t.scenario("sensory_feedback").build(t.context(UI, Host, Compose, env))
					return built.screen()
				end,
				{ frames = 12 }
			)
			local press = t.find(stage, "Press")
			t.check("press button mounted", press ~= nil and press:IsA("GuiButton"))
			t.check(
				"press button carries the native PressHapticEffect",
				press and press.PressHapticEffect == built.effects.press,
				press and press.PressHapticEffect
			)
			for kind, effect in built.effects :: { [string]: HapticEffect } do
				t.check(`{kind} effect is a native HapticEffect`, effect:IsA("HapticEffect"), effect.ClassName)
				t.note(`{kind} effect type`, effect.Type)
			end
			t.note("requests before input", built.requests:peek())
			t.hold(built)
		end,
	},
}
