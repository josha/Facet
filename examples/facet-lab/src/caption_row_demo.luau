--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

return function(UI: Controls): { Instance }
	local function circle(name: string, icon: string)
		return UI.Button(name) { name = name, icon = icon, shape = "circle", caption = name, controlSize = "regular" }
	end
	return {
		UI.Region "Actions" {
			zone = "bottomLeft",
			rank = 2,
			UI.HStack "ActionRow" {
				gap = "m",
				circle("Shop", "view.grid"),
				circle("Garage", "settings"),
				circle("Pass", "flag"),
			},
		},
		UI.Region "Race" { zone = "bottomRight", rank = 1, UI.Button { label = "Race", appearance = "emphasis" } },
	}
end
