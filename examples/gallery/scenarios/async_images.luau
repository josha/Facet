--!strict
-- Scenario 'async_images' (ledger rows NS-A13/NS-A14): the engine-free
-- resource provider drained by the REAL Roblox transport
-- (ContentProvider:PreloadAsync per-asset statuses). Three AsyncImages:
-- two real avatar thumbs (placeholder -> ready) and one invalid asset id
-- (placeholder -> failed). The releaseThird step proves HONEST cancellation:
-- releasing a handle makes any late completion stale and prevents unstarted
-- work — it never claims an in-flight fetch stopped.

return {
	title = "Async images via PreloadAsync (NS-A13/NS-A14)",
	ledgerRows = { "NS-A13", "NS-A14" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core
		local scope = core:scope()
		local provider = ctx.Facet.newResourceProvider(core)
		local unbindTransport = ctx.bindResourceTransport(provider)

		local imgs = {
			ctx.Facet.Controls.AsyncImage(core, {
				id = "AvatarRoblox",
				scope = scope,
				provider = provider,
				key = "rbxthumb://type=AvatarHeadShot&id=1&w=48&h=48",
			}),
			ctx.Facet.Controls.AsyncImage(core, {
				id = "AvatarBuilderman",
				scope = scope,
				provider = provider,
				key = "rbxthumb://type=AvatarHeadShot&id=156&w=48&h=48",
			}),
			ctx.Facet.Controls.AsyncImage(core, {
				id = "BadAsset",
				scope = scope,
				provider = provider,
				key = "rbxassetid://999999999999999",
			}),
		}

		local statusLine = core:memo(function(use)
			return string.format("1:%s 2:%s 3:%s", use(imgs[1].state), use(imgs[2].state), use(imgs[3].state))
		end)

		local screen = UI.Screen({
			id = "AsyncImages",
			padding = "m",
			gap = 12,
			children = {
				-- THE PAGE SCROLLS, and it did not until this fixture entered the demo
				-- picker (round-3 O-30). A title at 22pt, a status line and a row of
				-- thumbnails came to 25px more than a 640x320 landscape phone has, and
				-- 143px more under the largest text preference — a recorded, waived
				-- overflow for as long as the only thing that mounted this was a sweep.
				-- A surface a player can select does not get to overflow, so the waiver
				-- and its themed ledger row are deleted rather than re-recorded.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 12,
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = "Async images (PreloadAsync transport)", textSize = 22 }),
						UI.Text({ id = "Status", text = statusLine, textSize = "label" }),
						UI.HStack({
							id = "Row",
							gap = 12,
							wrap = true,
							width = UI.fill(),
							children = { imgs[1].blueprint, imgs[2].blueprint, imgs[3].blueprint },
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			steps = {
				-- honest-cancellation driver: release the second avatar's handle
				-- and try a stale completion against its old generation
				releaseSecond = function()
					local key = imgs[2].handle.key
					imgs[2].handle.release()
					local verdict = provider.complete(key, 1, key)
					return { verdict = verdict, stateAfter = imgs[2].state:get() }
				end,
			},
			report = function()
				return {
					states = { imgs[1].state:get(), imgs[2].state:get(), imgs[3].state:get() },
					errors = { tostring(imgs[3].handle.error:get()) },
				}
			end,
			dispose = function()
				unbindTransport()
				scope:dispose()
			end,
		}
	end,
}
