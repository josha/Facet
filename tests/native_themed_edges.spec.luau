--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local Facet = require("../src")
	local themes = Facet.themes
	local worlds = require("./lib/content_world")

	verifyHarness:suite("themed edges, plates and gutters", function()
		verifyHarness:case("keeps dense table rows flat while selection follows the model on skinned themes", {
			id = "native_themed_edges::themed edges, plates and gutters::keeps dense table rows flat while selection follows the model on skinned themes",
			run = function()
				local parchment = (require :: any)("../examples/themes/fantasy_parchment").build(themes)
				local selection = Facet.Compose.cell({ a = true } :: { [string]: boolean })
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Table({
						from = Facet.Compose.cell({ { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } }),
						key = "id",
						selection = selection,
						columns = {
							{
								id = "label",
								label = "Name",
								render = function(current): GuiObject
									return Host.TextLabel({ Text = current:peek().label })
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, { motionLevel = "none", theme = parchment })
				world.find("Body").AbsoluteWindowSize = world.V2(400, 300)
				local rows = {}
				for _, node in world.screen:GetDescendants() do
					if node:HasTag("facet-tablerow") then
						table.insert(rows, node)
					end
				end
				Verify.expect(#rows):toBe(2)
				for _, row in rows do
					Verify.expect((row:HasTag("facet-skinned"))):toBe(false)
					Verify.expect(row:FindFirstChild("Skin", true) == nil):toBe(true)
				end
				Verify.expect((rows[1]:HasTag("facet-selected"))):toBe(true)
				Verify.expect((rows[2]:HasTag("facet-selected"))):toBe(false)
				selection:set({ b = true })
				Verify.expect((rows[1]:HasTag("facet-selected"))):toBe(false)
				Verify.expect((rows[2]:HasTag("facet-selected"))):toBe(true)
				world.stop()
			end,
		})
	end)
end
