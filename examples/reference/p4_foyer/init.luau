--!strict
-- Reference proof "Foyer" (RA-P4, swiftui-reference-app-validation).
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

local Foyer = {}

local DESTINATIONS = { "home", "crews", "forge", "mail", "you" }
local DEST_ICON: { [string]: string } =
	{ home = "foyer:home", crews = "foyer:crews", forge = "foyer:forge", mail = "foyer:mail", you = "foyer:you" }

-- proof metrics (spec §5 proposes theme metrics; per package-briefs no new
-- theme tokens land this stage, so the values live here as the one substitute)
local TILE_MIN = 220
local SHELF_TILE = 96
local PORTRAIT = 56
local RAIL_W = 144
local DETAIL_W = 560
local SEARCH_W = 320
-- the count-bubble floor and pill cap (director review 2026-08-09): the floor
-- keeps one digit a legible circle, the cap holds "99+" without swallowing the
-- avatar it sits on
local BADGE_MIN = 20
local BADGE_MAX = 40

function Foyer.build(LuauUI: any, core: any, deps: any): any
	local UI = LuauUI.UI
	local env = deps.env
	local presenter = deps.presenter

	local scope = core:scope("ref-p4-foyer")
	local conditions = LuauUI.adaptive.conditions(core, env, { scope = scope })
	local clock = presenter.motionClock

	-- ── locale ─────────────────────────────────────────────────────────────
	local locale = core:signal("en")
	local stringMemos: { [string]: any } = {}
	local function L(key: string, param: string?): any
		local cacheKey = key .. "\1" .. (param or "")
		local m = stringMemos[cacheKey]
		if m == nil then
			m = core:memo(function(use)
				return strings.get(use(locale), key, param)
			end)
			stringMemos[cacheKey] = m
		end
		return m
	end
	local function Lnow(key: string, param: string?): string
		return strings.get(locale:get(), key, param)
	end

	-- ── services + images ──────────────────────────────────────────────────
	local services = Services.new({ core = core })
	local provider = LuauUI.newResourceProvider(core, { maxConcurrent = 4, cacheBudget = 64 })

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

	-- disposables from composite controls (newLabel/newTextInput) built at
	-- screen scope: owned here so dispose() releases them all
	local function owned(control: any): any
		if control.dispose ~= nil then
			scope:own(control.dispose)
		end
		return control
	end

	-- ── semantic state ─────────────────────────────────────────────────────
	local destination = core:signal("home")
	local tab = core:signal("forYou")
	local query = core:signal("")
	local filtered = services.filterMemo(query)
	local searchActive = core:memo(function(use)
		return use(query) ~= ""
	end)

	-- ── motion: tab underline springs (object class; reduced motion snaps) ──
	local function underlineTint(tabId: string)
		local s = clock:spring(if tab:get() == tabId then 1 else 0, "object")
		scope:own(core:observe(tab, function(now: string)
			s:setTarget(if now == tabId then 1 else 0)
		end))
		return core:memo(function(use)
			return { role = "accent", blend = use(s) }
		end)
	end

	-- ── feedback → proof sound ids (spec §12; ids only, nothing plays) ─────
	local soundLog: { string } = {}
	local FEEDBACK_SFX: { [string]: string } = {
		activate = "sfx.foyer.tap",
		commit = "sfx.foyer.done",
		reject = "sfx.foyer.deny",
		dismiss = "sfx.foyer.close",
	}
	scope:own(presenter.onFeedback(function(event: any)
		local id = FEEDBACK_SFX[event.type]
		if id ~= nil then
			table.insert(soundLog, id)
		end
	end))

	-- ── shared pieces ──────────────────────────────────────────────────────
	local function asyncImage(id: string, imgScope: any, key: string, width: any, height: any, radius: string?)
		local img = LuauUI.newAsyncImage(LuauUI, core, {
			id = id,
			scope = imgScope,
			provider = provider,
			key = key,
			width = width,
			height = height,
		})
		return UI.corners(img.blueprint, radius or "control")
	end

	local function toast(textKey: string)
		presenter.presentToast(
			UI.VStack({
				id = "ToastPlate",
				surface = "raised",
				padding = "m",
				children = { UI.Text({ id = "Msg", text = L(textKey), textSize = "label" }) },
			}),
			{ key = "foyer", duration = 4 }
		)
	end

	-- one modal shape for info surfaces (profile / notices / invite stub /
	-- see-all): a materializing raised panel with a Close button
	local function presentInfoModal(id: string, titleKey: string, bodyChildren: { any })
		local children: { any } = {
			UI.Text({ id = "Title", text = L(titleKey), textSize = "heading" }),
		}
		for _, child in bodyChildren do
			children[#children + 1] = child
		end
		local handle
		children[#children + 1] = UI.Button({
			id = "Close",
			label = Lnow("close.label"),
			onActivate = function()
				presenter.dismiss(handle)
			end,
		})
		handle = presenter.presentModal(
			UI.Screen({
				id = id,
				children = {
					UI.ZStack({
						id = "PanelZ",
						canvasGroup = true,
						children = {
							UI.corners(
								UI.shadow(
									UI.VStack({
										id = "Plate",
										surface = "raised",
										padding = "l",
										gap = "m",
										width = { type = "minMax", min = 280, max = DETAIL_W },
										children = children,
									}),
									"overlay"
								),
								"panel"
							),
						},
					}),
				},
			}),
			{ transition = { enter = "materialize" } }
		)
		return handle
	end

	local function presentNotices()
		local rows: { any } = {}
		for i, notice in seedData.notices :: { seedData.Notice } do
			rows[#rows + 1] = UI.VStack({
				id = "N" .. i,
				gap = "xs",
				children = {
					UI.Text({ id = "Body", text = notice.bodyKeyless }),
					UI.Text({
						id = "Time",
						text = L(notice.timeKey, notice.timeParam),
						textSize = "caption",
						role = "secondary",
					}),
				},
			})
		end
		presentInfoModal("NoticesModal", "notices.title", rows)
		services.clearNotices()
	end

	-- ── detail modal (spec §6.5) ───────────────────────────────────────────
	local detailScope: any = nil
	local function presentDetail(tile: seedData.Tile)
		if detailScope ~= nil then
			detailScope:dispose()
		end
		detailScope = core:scope("foyer-detail")
		local visitLabel = core:memo(function(use)
			local status = use(services.visitStatus)
			local pendingId = use(services.visitPendingId)
			if status == "pending" and pendingId == tile.id then
				return strings.get(use(locale), "detail.visiting")
			end
			return strings.get(use(locale), "detail.visit")
		end)
		local visitEnabled = core:memo(function(use)
			return use(services.visitStatus) ~= "pending"
		end)
		local handle
		handle = presenter.presentModal(
			UI.Screen({
				id = "Detail",
				children = {
					UI.ZStack({
						id = "PanelZ",
						canvasGroup = true,
						children = {
							UI.corners(
								UI.shadow(
									UI.VStack({
										id = "Plate",
										surface = "raised",
										padding = "l",
										width = { type = "minMax", min = 280, max = DETAIL_W },
										children = {
											UI.ScrollView({
												id = "Page",
												gap = "m",
												children = {
													asyncImage(
														"Hero",
														detailScope,
														tile.thumbKey,
														{ type = "fill", weight = 1 },
														{ type = "aspect", ratio = 16 / 9 }
													),
													UI.Text({ id = "Title", text = tile.title, textSize = "title" }),
													UI.Text({
														id = "Meta",
														text = tile.approval .. "%  ·  " .. tile.creator,
														textSize = "caption",
														role = "secondary",
													}),
													UI.Text({ id = "Blurb", text = tile.blurb }),
													UI.HStack({
														id = "Footer",
														gap = "m",
														children = {
															UI.Button({
																id = "Visit",
																label = visitLabel,
																surface = "accent",
																enabled = visitEnabled,
																onActivate = function()
																	services.visit(tile.id)
																end,
															}),
															UI.Spacer({}),
															UI.Button({
																id = "Close",
																label = Lnow("close.label"),
																shape = "circle",
																icon = "close",
																onActivate = function()
																	presenter.dismiss(handle)
																end,
															}),
														},
													}),
												},
											}),
										},
									}),
									"overlay"
								),
								"panel"
							),
						},
					}),
				},
			}),
			{ transition = { enter = "materialize" } }
		)
	end

	-- command outcomes (spec §9): visit confirm dismisses + toasts; refresh
	-- confirm toasts + scrolls the feed to top scenario-side; refresh reject
	-- toasts the service's reason key (already a full i18n key)
	scope:own(core:observe(services.visitStatus, function(status: string)
		if status == "confirmed" then
			-- back() is a safe no-op when no modal is up (it returns false)
			presenter.back()
			toast("toast.visited")
		elseif status == "rejected" then
			toast("err.generic")
		end
	end))
	scope:own(core:observe(services.refreshStatus, function(status: string)
		if status == "confirmed" then
			toast("toast.refreshed")
		elseif status == "rejected" then
			toast(services.refreshReason:get() or "err.generic")
		end
	end))

	-- ── tile card (spec §6.4) ──────────────────────────────────────────────
	local function tileCard(tile: seedData.Tile, itemScope: any)
		local approval = LuauUI.newLabel(LuauUI, core, {
			id = "Approval",
			title = tile.approval .. "%",
			icon = "foyer:approval",
		})
		if approval.dispose ~= nil then
			itemScope:own(approval.dispose)
		end
		local approvalB = LuauUI.newLabel(LuauUI, core, {
			id = "ApprovalB",
			title = tile.approval .. "%",
			icon = "foyer:approval",
		})
		if approvalB.dispose ~= nil then
			itemScope:own(approvalB.dispose)
		end
		return UI.Button({
			id = tile.id,
			label = tile.title,
			width = { type = "fill", weight = 1 },
			onActivate = function()
				presentDetail(tile)
			end,
			children = {
				UI.VStack({
					id = "Col",
					gap = "xs",
					align = "stretch",
					width = { type = "fill", weight = 1 },
					children = {
						asyncImage(
							"Thumb",
							itemScope,
							tile.thumbKey,
							{ type = "fill", weight = 1 },
							{ type = "aspect", ratio = 16 / 9 }
						),
						UI.Text({ id = "Title", text = tile.title, textSize = "label", lineLimit = 2 }),
						-- row when it fits, column at large type (large-text axis
						-- 2026-08-08: approval + Sponsored overflowed the cell by
						-- 9-14px at preference +14 — reflow, never squeeze)
						UI.ViewThatFits({
							id = "MetaFits",
							children = {
								UI.HStack({
									id = "MetaRow",
									gap = "xs",
									children = {
										approval.blueprint,
										UI.Spacer({}),
										UI.When({
											id = "Sponsored",
											condition = core:memo(function()
												return tile.sponsored
											end),
											thenView = function()
												return UI.Text({
													id = "Chip",
													surface = "chip",
													text = L("chip.sponsored"),
													textSize = "caption",
													role = "secondary",
												})
											end,
										}),
									},
								}),
								UI.VStack({
									id = "MetaColumn",
									gap = "xs",
									children = {
										approvalB.blueprint,
										UI.When({
											id = "SponsoredB",
											condition = core:memo(function()
												return tile.sponsored
											end),
											thenView = function()
												return UI.Text({
													id = "ChipB",
													surface = "chip",
													text = L("chip.sponsored"),
													textSize = "caption",
													role = "secondary",
												})
											end,
										}),
									},
								}),
							},
						}),
					},
				}),
			},
		})
	end

	-- ── section (grid or shelf) ────────────────────────────────────────────
	local function sectionView(section: any, itemScope: any)
		local header = UI.HStack({
			id = "Header",
			gap = "s",
			children = {
				UI.Text({ id = "Title", text = L(section.titleKey), textSize = "heading" }),
				UI.Spacer({}),
				UI.Button({
					id = "SeeAll",
					label = Lnow("section.seeAll", Lnow(section.titleKey)),
					shape = "circle",
					icon = "chevron.trailing",
					onActivate = function()
						local rows: { any } = {}
						for _, tile in section.tiles :: { seedData.Tile } do
							local t = tile
							rows[#rows + 1] = UI.Button({
								id = "All_" .. t.id,
								label = t.title,
								onActivate = function()
									presentDetail(t)
								end,
							})
						end
						presentInfoModal("SeeAll_" .. section.id, section.titleKey, rows)
					end,
				}),
			},
		})
		local body
		if section.layout == "shelf" then
			local shelfTiles: { any } = {}
			for _, tile in section.tiles :: { seedData.Tile } do
				local t = tile
				shelfTiles[#shelfTiles + 1] = UI.Button({
					id = "S_" .. t.id,
					label = t.title,
					onActivate = function()
						presentDetail(t)
					end,
					children = {
						UI.VStack({
							id = "Col",
							gap = "xs",
							children = {
								asyncImage(
									"Thumb",
									itemScope,
									t.thumbKey,
									{ type = "fixed", px = SHELF_TILE },
									{ type = "fixed", px = SHELF_TILE }
								),
								UI.Text({
									id = "Title",
									text = t.title,
									textSize = "caption",
									lineLimit = 1,
									disclose = true,
									width = { type = "fixed", px = SHELF_TILE },
								}),
							},
						}),
					},
				})
			end
			body = UI.ScrollView({ id = "Shelf", axis = "x", indicators = "none", gap = "s", children = shelfTiles })
		else
			body = UI.Grid({
				id = "Grid",
				minColumnWidth = TILE_MIN,
				itemSizing = "uniform",
				gap = "m",
				rowGap = "l",
				children = {
					UI.ForEach({
						id = "Tiles",
						items = core:memo(function()
							return section.tiles
						end),
						key = function(tile: seedData.Tile)
							return tile.id
						end,
						row = function(tile: seedData.Tile, rowScope: any)
							return tileCard(tile, rowScope)
						end,
					}),
				},
			})
		end
		return UI.VStack({ id = "Body", gap = "s", width = { type = "fill", weight = 1 }, children = { header, body } })
	end

	-- ── HomeBody (spec §6.3) ───────────────────────────────────────────────
	local function tabButton(tabId: string, labelKey: string)
		return UI.VStack({
			id = "Tab_" .. tabId,
			gap = "xs",
			children = {
				UI.Button({
					id = "B",
					label = L(labelKey),
					selected = core:memo(function(use)
						return use(tab) == tabId
					end),
					onActivate = function()
						tab:set(tabId)
					end,
				}),
				UI.Box({
					id = "Underline",
					height = { type = "fixed", px = 3 },
					width = { type = "fill", weight = 1 },
					tint = underlineTint(tabId),
				}),
			},
		})
	end

	-- THE BADGE (director review 2026-08-09: "we need better badging"). A count
	-- bubble is a MIN-SIZED round plate, never a bare glyph hugging its own
	-- pixels: the floor keeps one digit a circle, the pill cap holds 99+, the
	-- ring separates it from whatever it overlaps, and it sits ON the host's
	-- top-right corner. One builder, used at every badge site.
	local function badgeBubble(countMemo: any): any
		return UI.ZStack({
			id = "BadgeBubble",
			alignH = "end",
			alignV = "start",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.stroke(
					UI.Text({
						id = "Count",
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
			},
		})
	end

	local friendTiles: { any } = {
		UI.ZStack({
			id = "AddTile",
			children = {
				UI.Button({
					id = "B",
					label = Lnow("invite.label"),
					shape = "circle",
					icon = "foyer:add",
					width = { type = "fixed", px = PORTRAIT },
					onActivate = function()
						presentInfoModal("InviteStub", "invite.label", {
							UI.Text({ id = "StubBody", text = L("invite.stub"), role = "secondary" }),
						})
					end,
				}),
				UI.When({
					id = "BadgeWhen",
					condition = core:memo(function(use)
						return use(services.inviteCount) > 0
					end),
					thenView = function()
						return badgeBubble(core:memo(function(use)
							return tostring(use(services.inviteCount))
						end))
					end,
				}),
			},
		}),
	}
	for _, friend in services.friends :: { seedData.Friend } do
		local f = friend
		friendTiles[#friendTiles + 1] = UI.Button({
			id = "F_" .. f.id,
			label = f.handle,
			onActivate = function()
				presentInfoModal("Friend_" .. f.id, "profile.label", {
					UI.Text({ id = "FriendHandle", text = f.handle, textSize = "heading" }),
				})
			end,
			children = {
				UI.VStack({
					id = "Col",
					gap = "xs",
					children = {
						UI.ZStack({
							id = "PortraitZ",
							children = {
								asyncImage(
									"Portrait",
									scope,
									f.portraitKey,
									{ type = "fixed", px = PORTRAIT },
									{ type = "fixed", px = PORTRAIT },
									"pill"
								),
								UI.Box({
									id = "Presence",
									width = { type = "fixed", px = 10 },
									height = { type = "fixed", px = 10 },
									alignH = "end",
									alignV = "end",
									tint = {
										role = "accent",
										blend = if f.presence == "here" then 1 else 0,
									},
								}),
							},
						}),
						UI.Text({
							id = "Handle",
							text = f.handle,
							textSize = "caption",
							lineLimit = 1,
							disclose = true,
							width = { type = "fixed", px = PORTRAIT },
						}),
					},
				}),
			},
		})
	end

	local feedSections = core:memo(function(use)
		if use(searchActive) then
			return {}
		end
		if use(tab) == "charts" then
			return services.charted
		end
		return use(services.sections)
	end)

	local homeBody = UI.VStack({
		id = "HomeBody",
		gap = "m",
		align = "stretch",
		height = { type = "fill", weight = 1 },
		children = {
			UI.HStack({
				id = "TabRow",
				gap = "l",
				padding = { left = "m", right = "m" },
				children = { tabButton("forYou", "tab.forYou"), tabButton("charts", "tab.charts") },
			}),
			UI.ScrollView({
				id = "FeedPage",
				gap = "l",
				padding = "m",
				height = { type = "fill", weight = 1 },
				children = {
					UI.ScrollView({
						id = "FriendsRow",
						axis = "x",
						-- a peeking carousel's affordance IS the half-visible next
						-- tile — the reference app draws no bar on its carousels
						indicators = "none",
						gap = "s",
						width = { type = "fill", weight = 1 },
						children = friendTiles,
					}),
					UI.When({
						id = "SearchResults",
						condition = searchActive,
						thenView = function()
							return UI.VStack({
								id = "Results",
								gap = "s",
								width = { type = "fill", weight = 1 },
								children = {
									UI.When({
										id = "None",
										condition = core:memo(function(use)
											return #use(filtered) == 0
										end),
										thenView = function()
											return UI.VStack({
												id = "Empty",
												gap = "s",
												children = {
													UI.Text({
														id = "H",
														text = L("search.none"),
														textSize = "heading",
													}),
													UI.Text({
														id = "Q",
														text = core:memo(function(use)
															return '"' .. use(query) .. '"'
														end),
														lineLimit = 1,
														disclose = true,
													}),
													UI.Button({
														id = "Clear",
														label = Lnow("search.clear"),
														onActivate = function()
															query:set("")
														end,
													}),
												},
											})
										end,
									}),
									UI.ForEach({
										id = "Rows",
										items = filtered,
										key = function(tile: seedData.Tile)
											return tile.id
										end,
										row = function(tile: seedData.Tile, rowScope: any)
											return tileCard(tile, rowScope)
										end,
									}),
								},
							})
						end,
					}),
					UI.ForEach({
						id = "Sections",
						items = feedSections,
						key = function(section: any)
							return section.id
						end,
						row = function(section: any, rowScope: any)
							return sectionView(section, rowScope)
						end,
						transition = { enter = "slide-up" },
					}),
				},
			}),
		},
	})

	-- ── nav chrome (spec §6.2) ─────────────────────────────────────────────
	--
	-- THE FOUR NAV HOMES (adaptive.navPlacement, director ruling 2026-08-09):
	--   sidebar          desktop shape — the vertical rail, title and icon
	--   topBar           tablet / ten-foot shape — a CENTERED cluster that hugs
	--                    its wings, stepping down title+icon → icon-only by fit
	--   bottomBar        phone portrait — the full-width thumb-zone band
	--   bottomBarCompact phone landscape — the same band as a centered cluster
	--
	-- Both bottom homes are ICON-ONLY, which is the compact representation this
	-- proof already had and the reason no bottom wing can ever ellipsize
	-- (director refinement: "consider when to use the compact representation — I
	-- see a lot of cutoff text"). Only the SECTION NAV moves between homes: the
	-- top chrome bar, and the search that lives in it, is its own band and stays
	-- where it is on every placement.
	local function navItem(dest: string, presentation: string, width: any?)
		-- newLabel title is a plain string by contract: nav wing names are
		-- resolved at build locale (scenario reset re-resolves; body copy stays
		-- fully reactive through L() memos)
		local label = LuauUI.newLabel(LuauUI, core, {
			id = "L",
			title = Lnow("nav." .. dest),
			icon = DEST_ICON[dest],
			presentation = presentation,
		})
		if label.dispose ~= nil then
			scope:own(label.dispose)
		end
		return UI.Button({
			id = "Nav_" .. dest .. "_" .. presentation,
			label = Lnow("nav." .. dest),
			width = width,
			selected = core:memo(function(use)
				return use(destination) == dest
			end),
			onActivate = function()
				destination:set(dest)
			end,
			children = {
				UI.HStack({
					id = "Row",
					gap = "s",
					children = {
						UI.Box({
							id = "ActiveBar",
							width = { type = "fixed", px = 3 },
							height = { type = "fill", weight = 1 },
							tint = core:memo(function(use)
								return { role = "accent", blend = if use(destination) == dest then 1 else 0 }
							end),
						}),
						label.blueprint,
					},
				}),
			},
		})
	end

	-- Every home's wings are built ONCE, here, rather than inside a `When`'s
	-- factory: a wing carries a composite label with a disposer, and rebuilding
	-- the list on every mount would hand the screen scope a fresh set on every
	-- rotation. The homes below are mutually exclusive and declare no
	-- transitions, so no list is ever mounted in two places at the same time.
	local function navItems(presentation: string, width: any?): { any }
		local out: { any } = {}
		for _, dest in DESTINATIONS do
			out[#out + 1] = navItem(dest, presentation, width)
		end
		return out
	end

	local FILL = { type = "fill", weight = 1 }
	local NATURAL = { type = "content" }

	local placement = conditions.navPlacement
	local navSidebar = scope:own(core:memo(function(use)
		return use(placement) == "sidebar"
	end))
	local navTop = scope:own(core:memo(function(use)
		return use(placement) == "topBar"
	end))
	local navBottomFull = scope:own(core:memo(function(use)
		return use(placement) == "bottomBar"
	end))
	local navBottomCompact = scope:own(core:memo(function(use)
		return use(placement) == "bottomBarCompact"
	end))

	-- CONTENT, not hug, on the MEASURED candidates: `hug` caps at the offer, so a
	-- hug row can never tell a ViewThatFits that it does not fit — the ladder
	-- silently pins its first candidate and the wings truncate. `content` is the
	-- uncapped natural width, which is what a fit CHOICE needs; the chosen row is
	-- then centered by its `fill` wrapper and never stretched.
	local navTopBar = UI.VStack({
		id = "NavTopBar",
		align = "center",
		width = FILL,
		children = {
			UI.ViewThatFits({
				id = "NavTopFit",
				children = {
					UI.HStack({
						id = "NavTopFull",
						gap = "s",
						padding = { left = "s", right = "s" },
						-- NO `align` on a natural-width row: a container's own `align`
						-- is ALSO read by its PARENT as cross-axis alignment, so a
						-- "stretch" here would defeat the centering wrapper
						width = NATURAL,
						children = navItems("titleAndIcon"),
					}),
					UI.HStack({
						id = "NavTopIcons",
						gap = "s",
						padding = { left = "s", right = "s" },
						width = NATURAL,
						children = navItems("iconOnly"),
					}),
				},
			}),
		},
	})

	local navRail = UI.ScrollView({
		id = "NavRail",
		gap = "s",
		padding = "s",
		-- hugs its widest label within bounds so raised preferred text
		-- widens the rail instead of clipping it (large-text axis)
		width = { type = "minMax", min = RAIL_W, max = RAIL_W + 64 },
		height = { type = "fill", weight = 1 },
		children = navItems("titleAndIcon"),
	})

	local bottomBarFull = UI.HStack({
		id = "BottomBar",
		gap = "s",
		align = "stretch",
		width = FILL,
		children = navItems("iconOnly", FILL),
	})

	local bottomBarCompact = UI.VStack({
		id = "BottomCompactCenter",
		align = "center",
		width = FILL,
		children = {
			UI.HStack({
				id = "BottomCompact",
				gap = "s",
				width = NATURAL,
				children = navItems("iconOnly"),
			}),
		},
	})

	-- ── stub destinations (spec §6.6) ──────────────────────────────────────
	local function stubPlate()
		return UI.VStack({
			id = "StubPlate",
			gap = "s",
			align = "center",
			height = { type = "fill", weight = 1 },
			children = {
				UI.Text({
					id = "Name",
					text = core:memo(function(use)
						return strings.get(use(locale), "nav." .. use(destination))
					end),
					textSize = "heading",
				}),
				UI.Text({ id = "Body", text = L("stub.body") }),
				UI.Text({ id = "Honest", text = L("stub.honest"), textSize = "caption", role = "secondary" }),
			},
		})
	end

	-- ── top bar (spec §6.1) ────────────────────────────────────────────────
	local searchField = owned(LuauUI.newTextInput(LuauUI, core, {
		id = "Search",
		value = query,
		placeholder = Lnow("search.ph"),
		clearButtonMode = "whileEditing",
		env = env,
		actionSystem = deps.actionSystem,
	}))

	local topBar = UI.HStack({
		id = "TopBar",
		gap = "m",
		padding = "s",
		children = {
			UI.Text({ id = "Brand", text = L("app.name"), textSize = "title" }),
			UI.ViewThatFits({
				id = "SearchSlot",
				width = { type = "fill", weight = 1 },
				children = {
					UI.HStack({
						id = "FieldForm",
						width = { type = "minMax", min = 200, preferred = SEARCH_W, max = SEARCH_W },
						children = { searchField.blueprint },
					}),
					UI.Button({
						id = "IconForm",
						label = Lnow("search.label"),
						shape = "circle",
						icon = "foyer:search",
						onActivate = function()
							presentInfoModal("SearchModal", "search.label", {
								UI.Text({ id = "Hint", text = L("search.ph"), role = "secondary" }),
							})
						end,
					}),
				},
			}),
			UI.Button({
				id = "Refresh",
				label = Lnow("refresh.label"),
				shape = "circle",
				icon = "foyer:refresh",
				enabled = core:memo(function(use)
					return use(services.refreshStatus) ~= "pending"
				end),
				onActivate = function()
					services.refresh()
				end,
			}),
			-- a circle avatar chip at every width (the observed reference grammar;
			-- a hug text button can never engage the compact ladder — its box IS
			-- its label, framework-fixes ledger note)
			UI.Button({
				id = "Profile",
				label = Lnow("profile.label"),
				shape = "circle",
				icon = "foyer:you",
				onActivate = function()
					presentInfoModal("ProfileModal", "profile.label", {
						UI.Text({ id = "Caption", text = L("profile.caption"), role = "secondary" }),
					})
				end,
			}),
			UI.ZStack({
				id = "BellZ",
				children = {
					UI.Button({
						id = "Bell",
						label = Lnow("bell.label"),
						shape = "circle",
						icon = "foyer:bell",
						onActivate = presentNotices,
					}),
					UI.When({
						id = "BadgeWhen",
						condition = core:memo(function(use)
							return use(services.noticeCount) > 0
						end),
						thenView = function()
							return badgeBubble(core:memo(function(use)
								return tostring(use(services.noticeCount))
							end))
						end,
					}),
				},
			}),
		},
	})

	-- ── screen ─────────────────────────────────────────────────────────────
	local screen = UI.Screen({
		id = "Foyer",
		gap = "m",
		children = {
			UI.VStack({
				id = "Root",
				gap = "m",
				align = "stretch",
				height = { type = "fill", weight = 1 },
				children = {
					topBar,
					UI.When({
						id = "NavTopWhen",
						condition = navTop,
						thenView = function()
							return navTopBar
						end,
					}),
					UI.HStack({
						id = "Middle",
						gap = "m",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.When({
								id = "SideRailWhen",
								condition = navSidebar,
								thenView = function()
									return navRail
								end,
							}),
							UI.VStack({
								id = "ContentHost",
								gap = "m",
								align = "stretch",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								children = {
									UI.When({
										id = "HomeWhen",
										condition = core:memo(function(use)
											return use(destination) == "home"
										end),
										thenView = function()
											return homeBody
										end,
									}),
									UI.When({
										id = "StubWhen",
										condition = core:memo(function(use)
											return use(destination) ~= "home"
										end),
										thenView = stubPlate,
									}),
								},
							}),
						},
					}),
					UI.When({
						id = "BottomFullWhen",
						condition = navBottomFull,
						thenView = function()
							return bottomBarFull
						end,
					}),
					UI.When({
						id = "BottomCompactWhen",
						condition = navBottomCompact,
						thenView = function()
							return bottomBarCompact
						end,
					}),
				},
			}),
		},
	})

	-- The scripted transport rides the presenter's own tick (the one sanctioned
	-- frame source): every frame drains the provider's active window against the
	-- seed table, so a live session resolves art with no operator step while a
	-- headless test — which never ticks unless it chooses to — still observes
	-- the pending state and drives settleImages explicitly.
	scope:own(presenter.onTick(function()
		settleImages()
	end))
	settleImages()

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
		screen = screen,
		present = {
			keyboardNavigation = true,
			initialFocus = "first",
		},
		steps = steps,
		report = function()
			return {
				proof = "p4_foyer",
				destination = destination:get(),
				tab = tab:get(),
				query = query:get(),
				locale = locale:get(),
				noticeCount = services.noticeCount:get(),
				refreshStatus = services.refreshStatus:get(),
				visitStatus = services.visitStatus:get(),
				continueIds = services.continueIds:get(),
				providerCounters = provider.counters(),
				soundLog = soundLog,
				page = services.currentPage(),
			}
		end,
		dispose = function()
			if detailScope ~= nil then
				detailScope:dispose()
				detailScope = nil
			end
			scope:dispose()
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
