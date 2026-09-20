--!strict
-- Reference proof "Foyer" (RA-P4, reference-app-validation).
-- Clean-room discovery home surface built to specs/p4-foyer.md: nav rail ⇄
-- bottom bar chrome around one never-remounting HomeBody, ViewThatFits search
-- collapse, friends carousel, sectioned feed (uniform Grid + x-shelf), tile
-- detail modal with a visit command, notices/profile/stub surfaces, toasts,
-- and a deterministic fake service layer (services.luau). Engine-free: the
-- one engine-adjacent behavior (async image bytes) rides the provider's
-- transport seam, driven here by a scripted settle step so headless and Studio
-- runs resolve identically.

local strings = require("@self/content/strings")
local seedData = require("@self/content/seed")
local Services = require("@self/services")
--[[ THE CARVED BORDER, READ STRAIGHT OFF THE PUBLIC THEME SNAPSHOT.

	`chromeInsets` is documented theme-snapshot data — `docs/reference/api.md`
	"Art geometry: `chromeInsets`, `chromeOutsets` and `chromeBleed`" and
	`docs/guide/09-custom-themes.md`: `chromeInsets[slot] = {top, right, bottom,
	left}`, "Every slot publishes an entry, zero included", to be "read directly
	only when a caller must predict a decorated node's *content* box". The badge
	bubble below must land INSIDE its host's carved border, which is exactly
	that caller and the only reason this proof reads the map at all.

	WHAT USED TO BE HERE, AND WHY IT IS GONE. This read went through
	`src/tokens/chrome_slots.carvedSide`, reached by a two-route pcall (the
	ENGINE path `ReplicatedStorage.Facet.tokens.chrome_slots` first, the FILE
	path `require("../../src/tokens/chrome_slots")` second) plus a never-nil
	stub — the shape task SHOWCASE2 defect A introduced after a bare relative
	require resolved under Lune but NOT live in Studio, where Rojo folds this
	`init.luau` into `ReplicatedStorage.FacetReference.p4_foyer`, a SIBLING of
	`ReplicatedStorage.Facet` rather than a descendant. All of that existed only
	to reach a framework INTERNAL, which is what `tools/lune/check_boundary`'s
	`consumer-requires-facet-internal` rule flags an example for. The public
	field needs no resolution on either tree, so there is nothing left to
	resolve and no stub for a route that cannot fail.

	The local below keeps `carvedSide`'s exact defensiveness and its exact
	answers: a non-table snapshot, a missing slot, or a non-number side all read
	`0`, because a flat package legitimately carves nothing and that is not an
	error. Two call sites, one per axis — deliberately NOT a shared example
	utility module. ]]
local function carvedSide(snapshot: any?, slot: string, side: string): number
	if type(snapshot) ~= "table" then
		return 0
	end
	local insets = (snapshot :: any).chromeInsets
	local plate = if type(insets) == "table" then (insets :: any)[slot] else nil
	local px = if type(plate) == "table" then (plate :: any)[side] else nil
	return if type(px) == "number" then px else 0
end

local Foyer = {}

local DESTINATIONS = { "home", "crews", "forge", "mail", "you" }
local DEST_ICON: { [string]: string } =
	{ home = "foyer:home", crews = "foyer:crews", forge = "foyer:forge", mail = "foyer:mail", you = "foyer:you" }

-- proof metrics (spec §5 proposes theme metrics; per package-briefs no new
-- theme tokens land this stage, so the values live here as the one substitute)
local TILE_MIN = 220
local SHELF_TILE = 96
local PORTRAIT = 56
-- (the nav rail's own width used to live here; `newTabView` sizes its rail from
-- the theme's tap-target floor and its widest wing — navigation-and-menus D5)
local DETAIL_W = 560
local SEARCH_W = 320
-- the count-bubble floor and pill cap (director review 2026-08-09): the floor
-- keeps one digit a legible circle, the cap holds "99+" without swallowing the
-- avatar it sits on
local BADGE_MIN = 20
local BADGE_MAX = 40

function Foyer.build(Facet: any, core: any, deps: any): any
	local app = deps.app
	local UI = app.controls
	local Compose = Facet.Compose
	local env = app.environment
	local presenter = app.presenter

	-- A conditional region: `/<id>/then/...` or `/<id>/else/...`.
	local function when(id: string)
		return function(spec: any)
			return UI.When(id)({
				Compose.show(
					spec.condition,
					function()
						return UI.When("then")({ spec.thenView() })
					end,
					if spec.elseView
						then function()
							return UI.When("else")({ spec.elseView() })
						end
						else nil
				),
			})
		end
	end
	-- A keyed collection: each row lives at `/<id>/[key]/...`.
	local function forEach(id: string)
		return function(spec: any)
			return UI.ForEach(id)({
				Compose.keyed({
					from = spec.items,
					key = spec.key,
					render = function(item: any, _, key: any)
						local node = spec.row(item:peek())
						node.collectionKey = `[{key}]`
						return node
					end,
				}),
			})
		end
	end

	-- ── locale ─────────────────────────────────────────────────────────────
	local locale = Compose.cell("en")
	-- A reactive string: a property bound to it follows the locale.
	local function L(key: string, param: string?): any
		return function(use)
			return strings.get(use(locale), key, param)
		end
	end
	local function Lnow(key: string, param: string?): string
		return strings.get(locale:peek(), key, param)
	end

	-- ── services + images ──────────────────────────────────────────────────
	local services = Services.new({ Compose = Compose })
	local provider = Facet.newResourceProvider(core, { maxConcurrent = 4, cacheBudget = 64 })

	-- the scripted transport (spec §3): drain the provider's active window and
	-- resolve each key from the seed table — two keys scripted to fail. Looping
	-- because the active window is capped at maxConcurrent.
	local function settleImages()
		for _ = 1, 64 do
			local pending = provider.pendingRequests()
			if #pending == 0 then
				return
			end
			for _, req in pending do
				local ok, asset = seedData.assetFor(req.key)
				if ok then
					provider.complete(req.key, req.generation, asset)
				else
					provider.fail(req.key, req.generation, "scripted-failure")
				end
			end
		end
	end

	-- ── semantic state ─────────────────────────────────────────────────────
	local destination = Compose.cell("home")
	local tab = Compose.cell("forYou")
	local query = Compose.cell("")
	local filtered = services.filterMemo(query)
	local searchActive = Compose.formula(function(use)
		return use(query) ~= ""
	end)

	-- ── motion: tab underline springs (reduced motion snaps) ───────────────
	local function underlineTint(tabId: string)
		local s = app.runtime.spring(function(use)
			return if use(tab) == tabId then 1 else 0
		end, { period = 0.28, damping = 1 })
		return function(use)
			local blend = if use(env:get("reducedMotion")) then (if use(tab) == tabId then 1 else 0) else use(s)
			return { role = "accent", blend = math.clamp(blend, 0, 1) }
		end
	end

	-- ── feedback → proof sound ids (spec §12; ids only, nothing plays) ─────
	local soundLog: { string } = {}
	local FEEDBACK_SFX: { [string]: string } = {
		activate = "sfx.foyer.tap",
		commit = "sfx.foyer.done",
		reject = "sfx.foyer.deny",
		dismiss = "sfx.foyer.close",
	}
	local function logFeedback(event: any)
		local id = FEEDBACK_SFX[event.type]
		if id ~= nil then
			table.insert(soundLog, id)
		end
	end

	-- ── shared pieces ──────────────────────────────────────────────────────
	local function asyncImage(id: string, key: string, width: any, height: any, radius: string?)
		local img = UI.AsyncImage(id)({
			provider = provider,
			key = key,
			width = width,
			height = height,
		})
		return UI.corners(img, radius or "control")
	end

	-- A toast owns its body: the component runs inside the toast.
	local function toast(textKey: string)
		local function body()
			return UI.VStack("ToastPlate")({
				surface = "raised",
				padding = "m",
				UI.Text("Msg")({ text = L(textKey), textSize = "label" }),
			})
		end
		presenter.presentToast(body, { key = "foyer", duration = 4 })
	end

	-- one modal shape for info surfaces (profile / notices / invite stub /
	-- see-all): a materializing raised panel with a Close button
	-- `body` runs inside the modal's component and answers its middle children.
	local function presentInfoModal(id: string, titleKey: string, body: () -> { any })
		local close: any
		local function group()
			local props: { any } = {
				canvasGroup = true,
				UI.Text("Title")({ text = L(titleKey), textSize = "heading" }),
			} :: any
			for _, child in body() do
				table.insert(props, child)
			end
			table.insert(
				props,
				UI.Button("Close")({
					label = Lnow("close.label"),
					onActivate = function()
						close()
					end,
				})
			)
			return UI.ZStack("Group")(props)
		end
		--[[ task POP fix round 1: `Plate` is itself the panel (`surface =
			"raised"`) AND, before this fix, the direct container of `children`
			— `materialize` (which fades) targeted `PanelZ`, so `Plate` used to
			ride the same `GroupTransparency` ramp as its own title/body text
			(`newpop.mov`'s mechanism). `Plate` stays the outer, non-canvasGroup
			panel; `Group` is the ONE new canvasGroup, nested one level in. ]]
		close = app.presentModal(function()
			return UI.Screen(id)({

				UI.ZStack("PanelZ")({

					UI.corners(
						UI.shadow(
							UI.VStack("Plate")({
								surface = "raised",
								padding = "l",
								gap = "m",
								width = { type = "minMax", min = 280, max = DETAIL_W },

								group(),
							}),
							"overlay"
						),
						"panel"
					),
				}),
			})
		end, { transition = { enter = "materialize" } })
	end

	local function presentNotices()
		presentInfoModal("NoticesModal", "notices.title", function()
			local rows: { any } = {}
			for i, notice in seedData.notices :: { seedData.Notice } do
				rows[#rows + 1] = UI.VStack("N" .. i)({
					gap = "xs",

					UI.Text("Body")({ text = notice.bodyKeyless }),
					UI.Text("Time")({
						text = L(notice.timeKey, notice.timeParam),
						textSize = "caption",
						role = "secondary",
					}),
				})
			end
			return rows
		end)
		services.clearNotices()
	end

	-- ── detail modal (spec §6.5) ───────────────────────────────────────────
	local function presentDetail(tile: seedData.Tile)
		local visitLabel = Compose.formula(function(use)
			local status = use(services.visitStatus)
			local pendingId = use(services.visitPendingId)
			if status == "pending" and pendingId == tile.id then
				return strings.get(use(locale), "detail.visiting")
			end
			return strings.get(use(locale), "detail.visit")
		end)
		local visitEnabled = Compose.formula(function(use)
			return use(services.visitStatus) ~= "pending"
		end)
		local close: any
		-- `Plate` is the outer, non-canvasGroup panel; `Group` is the one
		-- canvasGroup, nested one level in, wrapping the page scroller.
		close = app.presentModal(function()
			return UI.Screen("Detail")({

				UI.ZStack("PanelZ")({

					UI.corners(
						UI.shadow(
							UI.VStack("Plate")({
								surface = "raised",
								padding = "l",
								width = { type = "minMax", min = 280, max = DETAIL_W },

								UI.ZStack("Group")({
									canvasGroup = true,

									UI.ScrollView("Page")({
										gap = "m",

										asyncImage(
											"Hero",
											tile.thumbKey,
											UI.fill(),
											{ type = "aspect", ratio = 16 / 9 }
										),
										UI.Text("Title")({
											text = tile.title,
											textSize = "title",
										}),
										UI.Text("Meta")({
											text = tile.approval .. "%  ·  " .. tile.creator,
											textSize = "caption",
											role = "secondary",
										}),
										UI.Text("Blurb")({ text = tile.blurb }),
										UI.HStack("Footer")({
											gap = "m",
											-- same story as the section Header: primary leading,
											-- dismiss trailing, said once on the row
											distribute = "spaceBetween",

											UI.Button("Visit")({
												label = visitLabel,
												surface = "accent",
												enabled = visitEnabled,
												onActivate = function()
													services.visit(tile.id)
												end,
											}),
											UI.Button("Close")({
												label = Lnow("close.label"),
												shape = "circle",
												icon = "close",
												onActivate = function()
													close()
												end,
											}),
										}),
									}),
								}),
							}),
							"overlay"
						),
						"panel"
					),
				}),
			})
		end, { transition = { enter = "materialize" } })
	end

	-- command outcomes (spec §9): visit confirm dismisses + toasts; refresh
	-- confirm toasts + scrolls the feed to top scenario-side; refresh reject
	-- toasts the service's reason key (already a full i18n key)
	local function watchStatus(source: any, onChange: (string) -> ())
		local first = true
		Compose.watch(function(use)
			local status = use(source)
			if first then
				first = false
				return
			end
			onChange(status)
		end)
	end
	local function watchCommands()
		watchStatus(services.visitStatus, function(status: string)
			if status == "confirmed" then
				-- back() is a safe no-op when no modal is up (it returns false)
				presenter.back()
				toast("toast.visited")
			elseif status == "rejected" then
				toast("err.generic")
			end
		end)
		watchStatus(services.refreshStatus, function(status: string)
			if status == "confirmed" then
				toast("toast.refreshed")
			elseif status == "rejected" then
				toast(services.refreshReason:peek() or "err.generic")
			end
		end)
	end

	-- ── tile card (spec §6.4) ──────────────────────────────────────────────
	local function tileCard(tile: seedData.Tile)
		local approval = UI.Label("Approval")({
			title = tile.approval .. "%",
			icon = "foyer:approval",
		})
		return UI.Button(tile.id)({
			label = tile.title,
			width = UI.fill(),
			onActivate = function()
				presentDetail(tile)
			end,

			UI.VStack("Col")({
				gap = "xs",
				align = "stretch",
				width = UI.fill(),

				asyncImage("Thumb", tile.thumbKey, UI.fill(), { type = "aspect", ratio = 16 / 9 }),
				UI.Text("Title")({ text = tile.title, textSize = "label", lineLimit = 2 }),
				--[[ THIS WAS A TWO-RUNG `ViewThatFits`: `MetaRow` (approval + a
							trailing Sponsored chip) with `MetaColumn` (the same two, stacked)
							behind it, because at preference +14 the pair overflowed the cell
							by 9-14px (large-text axis, 2026-08-08). The comment it carried
							said "REFLOW, NEVER SQUEEZE" — which is the definition of a flow
							wrap, hand-built out of the only parts that existed then.

							`wrap = true` (parity round 3) is that intent as one prop, and the
							ladder's cost goes with it: the column rung needed its OWN
							`newLabel` (`ApprovalB`, a second disposable control per tile) and
							its own `When`/`ChipB`, so every tile paid for two of everything
							and `Approval` was published at two paths, one of them always at a
							zero rect. One wrapping row, one label, one path each.

							THE `Spacer` WENT TOO, and had to: a `fill` main-axis child takes
							a whole line to itself in a wrapping stack, which the framework
							reports rather than silently doing. `distribute = "spaceBetween"`
							is the container-level word for what the Spacer was doing, and it
							acts PER LINE — so the chip is pushed to the trailing edge while
							the two share a line, and sits at the start of its own line once
							they do not. ]]
				UI.HStack("MetaFits")({
					wrap = true,
					gap = "xs",
					distribute = "spaceBetween",

					approval,
					when("Sponsored")({
						condition = Compose.formula(function()
							return tile.sponsored
						end),
						thenView = function()
							return UI.Text("Chip")({
								surface = "chip",
								text = L("chip.sponsored"),
								textSize = "caption",
								role = "secondary",
							})
						end,
					}),
				}),
			}),
		})
	end

	-- ── section (grid or shelf) ────────────────────────────────────────────
	local function sectionView(section: any)
		-- THE HEADER WRAPS (O-21, 2026-08-15): a heading and its trailing chevron
		-- have nothing shrinkable between them, and at +10/+14 on a 320px phone the
		-- `See all` target went 5px off the right screen edge on all four sections.
		local header = UI.HStack("Header")({
			wrap = true,
			gap = "s",
			-- `distribute` (parity round 2), not the `UI.Spacer({})` that used to sit
			-- between these two: title leading, action trailing is a property OF THE
			-- ROW, and saying it on the container survives a child appearing or
			-- disappearing, which a hand-placed separator does not
			distribute = "spaceBetween",

			UI.Text("Title")({ text = L(section.titleKey), textSize = "heading" }),
			UI.Button("SeeAll")({
				label = Lnow("section.seeAll", Lnow(section.titleKey)),
				shape = "circle",
				icon = "chevron.trailing",
				onActivate = function()
					presentInfoModal("SeeAll_" .. section.id, section.titleKey, function()
						local rows: { any } = {}
						for _, tile in section.tiles :: { seedData.Tile } do
							local t = tile
							rows[#rows + 1] = UI.Button("All_" .. t.id)({
								label = t.title,
								onActivate = function()
									presentDetail(t)
								end,
							})
						end
						return rows
					end)
				end,
			}),
		})
		local body
		if section.layout == "shelf" then
			local shelfTiles: any = { axis = "x", indicators = "none", gap = "s" }
			for _, tile in section.tiles :: { seedData.Tile } do
				local t = tile
				shelfTiles[#shelfTiles + 1] = UI.Button("S_" .. t.id)({
					label = t.title,
					onActivate = function()
						presentDetail(t)
					end,

					UI.VStack("Col")({
						gap = "xs",

						asyncImage(
							"Thumb",
							t.thumbKey,
							{ type = "fixed", px = SHELF_TILE },
							{ type = "fixed", px = SHELF_TILE }
						),
						UI.Text("Title")({
							text = t.title,
							textSize = "caption",
							lineLimit = 1,
							disclose = true,
							width = { type = "fixed", px = SHELF_TILE },
						}),
					}),
				})
			end
			body = UI.ScrollView("Shelf")(shelfTiles)
		else
			body = UI.Grid("Grid")({
				minColumnWidth = TILE_MIN,
				itemSizing = "uniform",
				gap = "m",
				rowGap = "l",

				forEach("Tiles")({
					items = Compose.formula(function()
						return section.tiles
					end),
					key = function(tile: seedData.Tile)
						return tile.id
					end,
					row = tileCard,
				}),
			})
		end
		return UI.VStack("Body")({ gap = "s", width = UI.fill(), header, body })
	end

	-- ── HomeBody (spec §6.3) ───────────────────────────────────────────────
	local function tabButton(tabId: string, labelKey: string)
		return UI.VStack("Tab_" .. tabId)({
			gap = "xs",
			-- both tabs give pixels back at the same rate, so a short row narrows
			-- them together instead of pushing the last one off the edge (O-21)
			shrinkWeight = 1,

			UI.Button("B")({
				label = L(labelKey),
				selected = Compose.formula(function(use)
					return use(tab) == tabId
				end),
				onActivate = function()
					tab:set(tabId)
				end,
			}),
			UI.Box("Underline")({
				height = { type = "fixed", px = 3 },
				width = UI.fill(),
				tint = underlineTint(tabId),
			}),
		})
	end

	-- THE BADGE (director review 2026-08-09: "we need better badging"). A count
	-- bubble is a MIN-SIZED round plate, never a bare glyph hugging its own
	-- pixels: the floor keeps one digit a circle, the pill cap holds 99+, the
	-- ring separates it from whatever it overlaps, and it sits ON the host's
	-- top-right corner. One builder, used at every badge site.
	--
	-- BADGE_CORNER_INSET (task FOYER, director order "fix foyer": the
	-- themed-chrome round recorded this builder as a third, deliberately-unfixed occurrence of the
	-- badge-corner-offset class closed this campaign in `src/controls/picker.
	-- luau`'s count seal and `examples/gallery/scenarios/adaptive_controls.
	-- luau`'s HUD-tile badge — the file's own name for this shape,
	-- `picker.luau`'s comment even citing "the `p4_foyer` badgeBubble shape"
	-- as its precedent). Both call sites below (`AddTile`'s invite count,
	-- `BellZ`'s notice count) decorate a `shape = "circle"` Button with no
	-- declared `surface`, which classifies to the same `control` slot by the
	-- CLASS-only fallback rule the framework's own classifier applies, so one
	-- memo, read live off the theme snapshot, covers both sites. PER AXIS
	-- (`carvedSide` at the top of this file, review finding T1): a corner
	-- offset pads two independent sides, and a scalar four-sided max
	-- over-clears the short axis of any package whose `control` chrome is not
	-- itself symmetric (fantasy_ornate: top=10, right=14). Zero on every flat
	-- package (`chromeInsets` is all-zero there), so shipped geometry there is
	-- unchanged.
	local badgeCornerInset = Compose.formula(function(use)
		local raw = use(env:get("themeMetrics"))
		local snap = if type(raw) == "table" and type((raw :: any).controls) == "table" then raw else nil
		return {
			top = carvedSide(snap, "control", "top"),
			right = carvedSide(snap, "control", "right"),
		}
	end)
	local function badgeBubble(countMemo: any): any
		return UI.ZStack("BadgeBubble")({
			alignH = "end",
			alignV = "start",
			width = UI.fill(),
			height = UI.fill(),
			-- clears the host's own carved `control` chrome border (see
			-- `badgeCornerInset` above); `{top=0,right=0}` on every flat
			-- package, so shipped geometry there is unchanged
			padding = badgeCornerInset,

			UI.stroke(
				UI.Text("Count")({
					surface = "badge",
					text = countMemo,
					textSize = "caption",
					textAlign = "center",
					lineLimit = 1,
					width = { type = "minMax", min = BADGE_MIN, max = BADGE_MAX },
					height = { type = "fixed", px = BADGE_MIN },
					corners = UI.cornersData("pill"),
				}),
				{}
			),
		})
	end

	-- ── the screen component ───────────────────────────────────────────────
	local function Screen()
		local conditions = Facet.adaptive.conditions(env)
		watchCommands()
		Compose.cleanup(presenter.onFeedback(logFeedback))
		-- The scripted transport rides the presenter's tick: every frame drains the
		-- provider's active window against the seed table. A headless test that never
		-- ticks still observes the pending state and drives settleImages itself.
		Compose.cleanup(presenter.onTick(settleImages))

		local friendTiles: any = {
			axis = "x",
			-- a peeking carousel's affordance is the half-visible next tile
			indicators = "none",
			gap = "s",
			width = UI.fill(),
			UI.ZStack("AddTile")({

				UI.Button("B")({
					label = Lnow("invite.label"),
					shape = "circle",
					icon = "foyer:add",
					width = { type = "fixed", px = PORTRAIT },
					onActivate = function()
						presentInfoModal("InviteStub", "invite.label", function()
							return { UI.Text("StubBody")({ text = L("invite.stub"), role = "secondary" }) }
						end)
					end,
				}),
				when("BadgeWhen")({
					condition = Compose.formula(function(use)
						return use(services.inviteCount) > 0
					end),
					thenView = function()
						return badgeBubble(Compose.formula(function(use)
							return tostring(use(services.inviteCount))
						end))
					end,
				}),
			}),
		}
		for _, friend in services.friends :: { seedData.Friend } do
			local f = friend
			friendTiles[#friendTiles + 1] = UI.Button("F_" .. f.id)({
				label = f.handle,
				onActivate = function()
					presentInfoModal("Friend_" .. f.id, "profile.label", function()
						return { UI.Text("FriendHandle")({ text = f.handle, textSize = "heading" }) }
					end)
				end,

				UI.VStack("Col")({
					gap = "xs",

					UI.ZStack("PortraitZ")({

						asyncImage(
							"Portrait",
							f.portraitKey,
							{ type = "fixed", px = PORTRAIT },
							{ type = "fixed", px = PORTRAIT },
							"pill"
						),
						UI.Box("Presence")({
							width = { type = "fixed", px = 10 },
							height = { type = "fixed", px = 10 },
							alignH = "end",
							alignV = "end",
							tint = {
								role = "accent",
								blend = if f.presence == "here" then 1 else 0,
							},
						}),
					}),
					UI.Text("Handle")({
						text = f.handle,
						textSize = "caption",
						lineLimit = 1,
						disclose = true,
						width = { type = "fixed", px = PORTRAIT },
					}),
				}),
			})
		end

		local feedSections = Compose.formula(function(use)
			if use(searchActive) then
				return {}
			end
			if use(tab) == "charts" then
				return services.charted
			end
			return use(services.sections)
		end)

		-- TabRow-to-FeedPage GAP IS "s", NOT "m" (overflow sweep, narrow-landscape
		-- 640x320): `FeedPage` is the spec's ONE scroll authority (§2) and stays
		-- `fill` — it is not this fixture's job to give IT more room, so the fix
		-- lives in what sits ABOVE it. `TabRow`'s two touch-target tabs are already
		-- their real, accessible height (not shrinkable), and at that viewport
		-- `Middle`'s box has exactly 64px for the whole of `HomeBody` — one `"m"`
		-- (16px) gap on top of TabRow's 53px already overflows the box before
		-- `FeedPage` gets a single pixel. One token step down closes it with room
		-- to spare, everywhere, and touches neither TabRow's touch targets nor
		-- FeedPage's own fill/scroll contract.
		local homeBody = UI.VStack("HomeBody")({
			gap = "s",
			align = "stretch",
			height = UI.fill(),

			--[[ THE TAB ROW SHRINKS RATHER THAN WRAPS (O-21 round 2, 2026-08-15).
				Wrapping was the first repair — two tab targets at the Largest text
				preference need more than a 320px phone gives them, and the row put
				`Charts` 27px off the right screen edge rather than taking a second
				line. Measured under the 1.4x `xa` locale it traded one loss for
				another: a second line is 63px, `Middle` leaves `HomeBody` about 64px
				on a 705x338 landscape, and the wrapped `Charts` tab then sat 5px BELOW
				the fold — the same label lost, off the other edge, and a tab target
				under the fold cannot even be aimed at.
				A wrapping stack does not read the shrink pair at all (api.md:
				"wrapping IS what this stack does with a deficit"), so the two are
				alternatives rather than a pair. Shrinking keeps both targets on ONE
				line and on screen at every viewport and every locale; the cost is a
				truncated tab label at the far end of the cross product, which is a
				degrade the framework has a name for and an off-screen target is not. ]]
			UI.HStack("TabRow")({
				gap = "l",
				padding = { left = "m", right = "m" },
				tabButton("forYou", "tab.forYou"),
				tabButton("charts", "tab.charts"),
			}),
			-- PADDING IS "s", NOT "m" (overflow sweep + live report: this scroll —
			-- the spec's ONE scroll authority, §2 — was already silently drawing
			-- NOTHING on the canonical compact-phone-landscape row, 705x338: its own
			-- 16+16 padding alone exceeded the 13px TabRow left it, before this fix
			-- even touched HomeBody's gap. A smaller, still-real padding step gives
			-- it an honest content box on every viewport that has room for a feed at
			-- all; the narrowest swept viewport (640x320) has so little of Middle's
			-- box left after TabRow's own accessible height that no padding choice
			-- can make FeedPage show content there without shrinking a real touch
			-- target — that residual is reported, not hidden.
			UI.ScrollView("FeedPage")({
				gap = "l",
				padding = "s",
				height = UI.fill(),

				UI.ScrollView("FriendsRow")(friendTiles),
				when("SearchResults")({
					condition = searchActive,
					thenView = function()
						return UI.VStack("Results")({
							gap = "s",
							width = UI.fill(),

							when("None")({
								condition = Compose.formula(function(use)
									return #use(filtered) == 0
								end),
								thenView = function()
									return UI.VStack("Empty")({
										gap = "s",

										UI.Text("H")({
											text = L("search.none"),
											textSize = "heading",
										}),
										UI.Text("Q")({
											text = Compose.formula(function(use)
												return '"' .. use(query) .. '"'
											end),
											lineLimit = 1,
											disclose = true,
										}),
										UI.Button("Clear")({
											label = Lnow("search.clear"),
											onActivate = function()
												query:set("")
											end,
										}),
									})
								end,
							}),
							forEach("Rows")({
								items = filtered,
								key = function(tile: seedData.Tile)
									return tile.id
								end,
								row = tileCard,
							}),
						})
					end,
				}),
				forEach("Sections")({
					items = feedSections,
					key = function(section: any)
						return section.id
					end,
					row = sectionView,
					transition = { enter = "slide-up" },
				}),
			}),
		})

		-- ── nav chrome (spec §6.2) — ONE `Facet.newTabView`, built below ──────
		--
		-- THE FOUR NAV HOMES ARE NO LONGER THIS FILE'S BUSINESS (navigation-and-menus
		-- D5). `adaptive.navPlacement` shipped 2026-08-09 and every reference app
		-- then wrote the same four `When`-gated presentations by hand; D5 turned that
		-- into a construct and this proof is its first consumer. What used to stand
		-- here — four placement memos, four hand-built bars, three copies of the wing
		-- list, a hand-rolled 3px active bar and a `ViewThatFits` ladder per home — is
		-- now a `tabs` array handed to `newTabView` beside the screen, using the
		-- `conditions` this file already builds.
		--
		-- Only the SECTION NAV ever moved between homes: the top chrome bar, and the
		-- search that lives in it, is its own band and stays where it is on every
		-- placement. That is why this proof could adopt the construct whole rather
		-- than borrowing pieces of it.
		--
		-- FOUR VISIBLE CHANGES, each a deliberate trade rather than an oversight:
		--
		--  1. THE ACTIVE BAR IS THE FRAMEWORK'S SLIDING INDICATOR. The 3px rule this
		--     file painted inside every wing is exactly D4's `underline`, and the
		--     framework's one SLIDES between wings instead of cross-fading two fills.
		--  2. ICON-ONLY IS A FIT DECISION NOW, NOT A PER-HOME ONE. The bottom homes
		--     hard-coded it so no wing could ellipsize; `Option.icon` rides
		--     `compactLabel`, so the framework degrades word -> glyph at the width
		--     that actually needs it and never ellipsizes either. Same guarantee, one
		--     fewer rule, and the rail and top band keep their words for free.
		--  3. THE WING NAMES NOW FOLLOW A LIVE LOCALE FLIP. `newLabel`'s title is a
		--     plain string by contract, so the old wings resolved at BUILD locale and
		--     this proof's own loop could not move them; a picker option label may be
		--     a Readable, so they are `L(...)` memos and they do.
		--  4. THE TOP AND COMPACT BANDS LEAD RATHER THAN CENTRE. A tab bar that can
		--     OVERFLOW is a scroll host, and a scroll host cannot centre content
		--     narrower than its band — measured, not assumed: a `fill` child inside a
		--     horizontal ScrollView resolves to the CONTENT width, so there is no band
		--     width to centre within. Five wings that scroll beat five wings that
		--     centre and truncate.

		-- ── stub destinations (spec §6.6) ──────────────────────────────────────
		local function stubPlate()
			return UI.VStack("StubPlate")({
				gap = "s",
				align = "center",
				height = UI.fill(),

				UI.Text("Name")({
					text = Compose.formula(function(use)
						return strings.get(use(locale), "nav." .. use(destination))
					end),
					textSize = "heading",
				}),
				UI.Text("Body")({ text = L("stub.body") }),
				UI.Text("Honest")({ text = L("stub.honest"), textSize = "caption", role = "secondary" }),
			})
		end

		-- ── top bar (spec §6.1) ────────────────────────────────────────────────
		local searchField = UI.TextInput("Search")({
			value = query,
			placeholder = Lnow("search.ph"),
			clearButtonMode = "whileEditing",
			env = env,
			actionSystem = deps.actionSystem,
		})

		local topBar = UI.HStack("TopBar")({
			gap = "m",
			padding = "s",

			--[[ WHY THE SHRINK PAIR BELOW NEEDED A `minMax` UNDER IT. This row reports
				"content overflows this hstack by 46px on the main axis" on
				`controller.diagnostics()` at 390x844 with `preferredTextSize` raised to
				+4 and +14 — the phone, at two of the four shipping text offsets. (The
				proof's five-view sweep raises `displaySize`, never `preferredTextSize`,
				which is why it never said so; the sweep now covers the offsets.)

				Round 2's `layoutPriority`/`shrinkWeight` LOOK like the answer and are
				not. Tried 2026-08-13 (`Brand` tier 0 weight 1, `SearchSlot` tier 1);
				the overflow stayed at exactly 46px and the framework said why:
				"every shrinkable child is already at its floor (layoutPriority order
				tried: 0)". A text node's shrink floor is ITS LONGEST WORD, and the
				brand is the single word "Foyer" — which measures 224px at title+4, so
				there is nothing for a weight to give. The prop was deleted rather than
				left in place looking like a fix, and the gap was recorded in the
				round-3 adoption ledger: no vocabulary lets a one-word label truncate
				BELOW its longest word, so a hand-chosen `minMax` is the only lever.
				O-21 took it — see the node below; the pair is back BECAUSE the floor
				it needed is now declared, which is the part that was missing. ]]
			UI.Text("Brand")({
				text = L("app.name"),
				textSize = "title",
				--[[ THE SHRINK PAIR IS BACK, AND THE BLOCK ABOVE IS WHY IT WORKS NOW
					(O-21, measured 2026-08-15). That note is from 2026-08-13 and its
					conclusion — "no vocabulary lets a one-word label truncate BELOW its
					longest word, so a hand-chosen `minMax` cap is still the only lever" —
					was true on the day it was written and is not true today: director
					ruling 1 of 2026-08-14 put an ELLIPSIS rung under the longest-word
					floor (`src/layout/shrink.luau`, COMPACT -> TRUNCATE -> CLIP), so a
					single-word wordmark has somewhere to go and a bare `shrinkWeight`
					reaches it. MEASURED AS THE MINIMAL SET: a `minMax` with a zero floor under
					this was written first and then deleted, because removing it moves
					neither the sweep nor the readability probe — the cascade already
					supplies the floor it was there to declare. Removing the weight
					itself reddens `proof 'p4_foyer'`.
					What it buys: without it the bell and its unread count sat 2px off a
					320px screen in English at +14, and 19px off a 390px one under `xa`. ]]
				shrinkWeight = 1,
				-- ...and a cut wordmark is a DECLARED truncation with a way back
				-- (§15.3 `policy = "truncate"`), never a clipped string. No always-on
				-- check bites for these two — the probe only reads nodes under a
				-- finding, and this row files none now — so they are here on the
				-- standing rule that player copy is never cut without an opener.
				lineLimit = 1,
				disclose = true,
			}),
			UI.ViewThatFits("SearchSlot")({
				width = UI.fill(),
				layoutPriority = 1,

				UI.HStack("FieldForm")({
					width = { type = "minMax", min = 200, preferred = SEARCH_W, max = SEARCH_W },
					searchField,
				}),
				UI.Button("IconForm")({
					label = Lnow("search.label"),
					shape = "circle",
					icon = "foyer:search",
					onActivate = function()
						presentInfoModal("SearchModal", "search.label", function()
							return { UI.Text("Hint")({ text = L("search.ph"), role = "secondary" }) }
						end)
					end,
				}),
			}),
			UI.Button("Refresh")({
				label = Lnow("refresh.label"),
				shape = "circle",
				icon = "foyer:refresh",
				enabled = Compose.formula(function(use)
					return use(services.refreshStatus) ~= "pending"
				end),
				onActivate = function()
					services.refresh()
				end,
			}),
			-- a circle avatar chip at every width (the observed reference grammar;
			-- a hug text button can never engage the compact ladder — its box IS
			-- its label, framework-fixes ledger note)
			UI.Button("Profile")({
				label = Lnow("profile.label"),
				shape = "circle",
				icon = "foyer:you",
				onActivate = function()
					presentInfoModal("ProfileModal", "profile.label", function()
						return { UI.Text("Caption")({ text = L("profile.caption"), role = "secondary" }) }
					end)
				end,
			}),
			UI.ZStack("BellZ")({

				UI.Button("Bell")({
					label = Lnow("bell.label"),
					shape = "circle",
					icon = "foyer:bell",
					onActivate = presentNotices,
				}),
				when("BadgeWhen")({
					condition = Compose.formula(function(use)
						return use(services.noticeCount) > 0
					end),
					thenView = function()
						return badgeBubble(Compose.formula(function(use)
							return tostring(use(services.noticeCount))
						end))
					end,
				}),
			}),
		})

		-- ── the nav, as ONE construct (navigation-and-menus D5) ────────────────
		--
		-- Five destinations, five tab bodies, and the placement policy. `homeBody` is
		-- still built ONCE above and merely CAPTURED by its factory — the wings'
		-- disposer lesson has not changed, and a tab factory that rebuilt a composite
		-- on every visit would hand the screen scope a fresh set each time. The stubs
		-- own nothing, so they are rebuilt, which is exactly what the construct's
		-- eviction contract promises: coming back replays the entry cost.
		local navTabs: { any } = {}
		for _, dest in DESTINATIONS do
			table.insert(navTabs, {
				id = dest,
				label = L("nav." .. dest),
				icon = DEST_ICON[dest],
				content = if dest == "home"
					then function()
						return homeBody
					end
					else function()
						return stubPlate()
					end,
			})
		end
		local nav = UI.TabView("Nav")({
			selection = destination,
			-- the conditions this screen already builds, passed in rather than rebuilt:
			-- `adaptive.conditions` creates its own set of memos and two copies would be two
			-- answers to one question
			conditions = conditions,
			env = env,
			tabs = navTabs,
		})

		-- ── screen ─────────────────────────────────────────────────────────────
		local screen = UI.Screen("Foyer")({
			gap = "m",

			UI.VStack("Root")({
				gap = "m",
				align = "stretch",
				height = UI.fill(),

				-- the chrome band, which never moves…
				topBar,
				-- …and everything the placement policy DOES move, which is now
				-- one node instead of four `When`s around three copies of a list
				nav,
			}),
		})

		settleImages()
		return screen
	end

	local steps = {
		locale = function(_built: any, value: string?)
			locale:set(if value == "xa" then "xa" else "en")
		end,
		destination = function(_built: any, value: string?)
			if value ~= nil then
				destination:set(value)
			end
		end,
		tab = function(_built: any, value: string?)
			if value ~= nil then
				tab:set(value)
			end
		end,
		search = function(_built: any, value: string?)
			query:set(value or "")
		end,
		refresh = function()
			services.refresh()
		end,
		rejectNextRefresh = function()
			services.scriptRejection("refresh", "err.feed.refresh.offline")
		end,
		rejectNextVisit = function()
			services.scriptRejection("visit", "err.generic")
		end,
		settle = function()
			services.settle()
		end,
		settleImages = settleImages,
	}

	return {
		screen = Screen,
		present = {
			keyboardNavigation = true,
			initialFocus = "first",
		},
		steps = steps,
		report = function()
			return {
				proof = "p4_foyer",
				destination = destination:peek(),
				tab = tab:peek(),
				query = query:peek(),
				locale = locale:peek(),
				noticeCount = services.noticeCount:peek(),
				refreshStatus = services.refreshStatus:peek(),
				visitStatus = services.visitStatus:peek(),
				continueIds = services.continueIds:peek(),
				providerCounters = provider.counters(),
				soundLog = soundLog,
				page = services.currentPage(),
			}
		end,
		-- exposed for the proof's own spec file (never for consumers)
		_internals = {
			services = services,
			provider = provider,
			signals = { destination = destination, tab = tab, query = query, locale = locale },
			settleImages = settleImages,
		},
	}
end

return Foyer
