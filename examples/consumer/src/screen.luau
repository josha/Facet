--!strict
local screen = {}
function screen.build(Facet: any, UI: any)
	local Compose = Facet.Compose
	local count = Compose.cell(0)
	local sound = Compose.cell(true)
	local visible = Compose.cell(true)
	return UI.Screen "Consumer" {
		Compose.show(visible, function()
			return UI.VStack "Panel" {
				gap = "s",
				width = "fill",
				align = "stretch",
				UI.Label "Title" { text = "Facet consumer", textRole = "title" },
				UI.Label "Blurb" {
					text = "One component, local state, one theme. Press Bump and watch the count follow.",
					textRole = "caption",
					TextWrapped = true,
				},
				UI.Label "Count" {
					text = function(use)
						return if use(count) == 1 then "1 tap" else `{use(count)} taps`
					end,
					textRole = "heading",
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
