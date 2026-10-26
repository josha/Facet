--!strict
type Live = {
	Facet: typeof(require("@repo/src")),
	settle: (number?) -> (),
	check: (string, boolean, unknown?) -> (),
}

return {
	{
		id = "compose-design-kit-opens-the-facet-editor",
		contracts = { "Facet.composeDesign" },
		run = function(t: Live)
			local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local screen = Instance.new("ScreenGui")
			screen.Name = "ComposeDesignLive"
			screen.ResetOnSpawn = false
			screen.Parent = playerGui
			local opened, result = pcall(function()
				return t.Facet.composeDesign().edit(screen, "Screen")
			end)
			t.check("the Facet kit opens without an error", opened, if opened then nil else tostring(result))
			t.settle(4)
			local inspector = screen:FindFirstChild("InspectorPanel", true)
			local library = screen:FindFirstChild("LibraryPanel", true)
			t.check("the inspector and library panels mount", inspector ~= nil and library ~= nil)
			local theme = screen:FindFirstChild("FacetTheme", true)
			t.check("the staged design sits inside the Facet theme", theme ~= nil and theme:IsA("GuiObject"))
			local link = if theme then theme:FindFirstChildWhichIsA("StyleLink") else nil
			t.check("the theme StyleSheet is linked", link ~= nil and typeof(link.StyleSheet) == "Instance")
			if opened then
				result.dispose()
			end
			screen:Destroy()
		end,
	},
}
