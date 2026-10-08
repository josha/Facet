--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
return {
	{
		id = "haptics-mount-feedback-demo",
		contracts = {},
		run = function(t: any)
			local built
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
				built = t.scenario("sensory_feedback").build(t.context(UI, Host, Compose, env))
				return built.screen()
			end, { frames = 12 })
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
