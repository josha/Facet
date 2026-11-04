--!strict
local Shared = require("./types")
local Controls = require("./control_types")

return function(ctx: Shared.Context, UI: Controls.Controls)
	local Compose, runtime, Host = ctx.Compose, ctx.runtime, ctx.Host
	UI.worldSurface = function(layer: BillboardGui | SurfaceGui, content: () -> Instance): Folder
		assert(
			layer:IsA("BillboardGui") or layer:IsA("SurfaceGui"),
			"Facet worldSurface requires BillboardGui or SurfaceGui"
		)
		local anchor = Host.Folder "WorldSurface" {}
		local link = Compose.cell<<StyleLink?>>(nil)
		local function locate()
			local at: Instance? = anchor.Parent
			local nearest: StyleLink? = nil
			while at do
				local found = at:FindFirstChildWhichIsA("StyleLink")
				if found and found:IsA("StyleLink") then
					nearest = found
					break
				end
				at = at.Parent
			end
			link:set(nearest)
		end
		runtime.connect(anchor, "AncestryChanged", locate)
		runtime.mountFragment(function()
			return {
				Compose.portal(layer, function()
					local sheet = Compose.cell<<StyleSheet?>>(nil)
					Compose.watch(function(use: Shared.Use)
						local inherited = use(link)
						if inherited then
							local source = runtime.observe(inherited, "StyleSheet")
							Compose.watch(function(read: Shared.Use)
								local value = read(source)
								sheet:set(
									if typeof(value) == "Instance" and value:IsA("StyleSheet") then value else nil
								)
							end)
						else
							sheet:set(nil)
						end
					end)
					return { Host.StyleLink { StyleSheet = sheet }, content() }
				end),
			}
		end, anchor)
		locate()
		return anchor
	end
end
