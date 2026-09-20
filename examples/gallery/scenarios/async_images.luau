--!strict
-- Scenario 'async_images' (ledger rows NS-A13/NS-A14): the engine-free
-- resource provider drained by the REAL Roblox transport
-- (ContentProvider:PreloadAsync per-asset statuses). Three AsyncImages:
-- two real avatar thumbs (placeholder -> ready) and one invalid asset id
-- (placeholder -> failed). The releaseThird step proves HONEST cancellation:
-- releasing a handle makes any late completion stale and prevents unstarted
-- work — it never claims an in-flight fetch stopped.

return {
	title = "Loading profile pictures",
	ledgerRows = { "NS-A13", "NS-A14" },
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local provider = ctx.Facet.newResourceProvider(ctx.core)
		local unbindTransport = ctx.bindResourceTransport(provider)

		local pictures = {
			{ id = "AvatarRoblox", key = "rbxthumb://type=AvatarHeadShot&id=1&w=48&h=48" },
			{ id = "AvatarBuilderman", key = "rbxthumb://type=AvatarHeadShot&id=156&w=48&h=48" },
			{ id = "BadAsset", key = "rbxassetid://999999999999999" },
		}
		-- The page keeps its own lease on each key, so the status line and the
		-- report read the same state the pictures show.
		local leases: { any } = {}
		local secondShown = Compose.cell(true)

		local function picture(index: number)
			return UI.AsyncImage(pictures[index].id)({ provider = provider, key = pictures[index].key })
		end

		local function Example()
			local owner = Compose.currentOwner()
			for index, entry in pictures do
				leases[index] = provider.acquire(owner, entry.key)
			end
			local statusLine = Compose.formula(function(use)
				return string.format(
					"Roblox: %s • Builderman: %s • Unavailable picture: %s",
					use(leases[1].state),
					use(leases[2].state),
					use(leases[3].state)
				)
			end)
			return UI.Screen("AsyncImages")({
				padding = "m",
				gap = 12,

				-- The page scrolls: a title, a status line and a row of thumbnails
				-- exceed a 640x320 landscape phone, more so under large text.
				UI.ScrollView("Page")({
					axis = "y",
					gap = 12,
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = "Loading profile pictures", textSize = "title" }),
					UI.Text("Explanation")({
						text = "Pictures can arrive later than the page. These keep their space while loading; an unavailable picture keeps a placeholder.",
						textSize = "body",
					}),
					UI.Text("Status")({ text = statusLine, textSize = "label" }),
					UI.HStack("Row")({
						gap = 12,
						wrap = true,
						width = UI.fill(),
						picture(1),
						Compose.show(secondShown, function()
							return picture(2)
						end),
						picture(3),
					}),
				}),
			})
		end

		return {
			screen = Example,
			present = {},
			steps = {
				-- honest-cancellation driver: release every lease on the second
				-- avatar and try a stale completion against its old generation
				releaseSecond = function()
					local lease = leases[2]
					secondShown:set(false)
					lease.release()
					local verdict = provider.complete(lease.key, 1, lease.key)
					return { verdict = verdict, stateAfter = lease.state:peek() }
				end,
			},
			report = function()
				return {
					states = { leases[1].state:peek(), leases[2].state:peek(), leases[3].state:peek() },
					errors = { tostring(leases[3].error:peek()) },
				}
			end,
			dispose = function()
				unbindTransport()
				provider.dispose()
			end,
		}
	end,
}
