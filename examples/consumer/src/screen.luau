--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local screen = {}
function screen.build(Facet: any, UI: any)
	local Compose: ComposeModule = Facet.Compose
	local count = Compose.cell(0)
	local sound = Compose.cell(true)
	local visible = Compose.cell(true)
	return UI.Screen "Consumer" {
		Compose.show(visible, function()
			return UI.VStack "Panel" {
				BackgroundTransparency = 0,
				padding = "m",
				ref = function(node: Frame)
					node:AddTag("facet-surface")
				end,
				gap = "s",
				width = "fill" :: "fill",
				align = "stretch" :: "stretch",
				UI.Text "Title" { text = "Facet consumer", textRole = "title" :: "title" } :: unknown,
				UI.Text "Blurb" {
					text = "One component, local state, one theme. Press Bump and watch the count follow.",
					textRole = "caption" :: "caption",
					TextWrapped = true,
				},
				UI.Text "Count" {
					text = function(use: Use)
						return if use(count) == 1 then "1 tap" else `{use(count)} taps`
					end,
					textRole = "heading" :: "heading",
				},
				UI.Toggle "Sound" { label = "Sound", value = sound },
				UI.Button "Bump" {
					label = "Bump",
					appearance = "emphasis",
					onActivate = function()
						count:update(function(value: number): number
							return value + 1
						end)
					end,
				},
				UI.Button "Close" {
					label = "Close",
					onActivate = function()
						visible:set(false)
					end,
				},
			}
		end),
	}
end
return screen
