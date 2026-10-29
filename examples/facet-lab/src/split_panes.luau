--!strict
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

return function(UI: FacetControls)
	return {
		sidebar = function(): Instance
			local rows: StackProps = { width = "fill", gap = "xs", padding = "s" }
			for _, name in { "Files", "Coast.png", "Forest.mat" } do
				rows[#rows + 1] = UI.Button { label = name, Size = UDim2.fromScale(1, 0) }
			end
			return UI.VStack(rows)
		end,
		detail = function(): Instance
			return UI.VStack {
				width = "fill",
				padding = "m",
				UI.Text { text = "Linked files", textRole = "heading" },
				UI.Text { text = "Drag the divider to resize.", role = "secondary" },
			}
		end,
	}
end
