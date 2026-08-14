--!strict
-- Reference proof "Wardrobe" (RA-P5, swiftui-reference-app-validation).
-- Clean-room avatar-editor surface built to specs/p5-wardrobe.md: one
-- Composition (split ⇄ stacked by lane floor, never a device branch), a
-- UI.Stage preview pane whose blocky mannequin the proof dresses through the
-- runner's data seam, orbit on all four input classes (Grip drag + focus-gated
-- Adjust), try-on with undo/redo history, a Sparks wallet, and a full
-- purchase-shaped lifecycle with visible rejections. SELF-PRESENTING: build
-- presents and returns { handle } so the proof owns the controller its stage
-- wiring needs; the runner will not present it twice (built.handle set).

local strings = require("@self/content/strings")
local seedData = require("@self/content/seed")
local Services = require("@self/services")

local Wardrobe = {}

local CARD_MIN = 148
local PREVIEW_LANE_MIN = 280
local CONFIRM_W = 420
local SPARK = "✦"

local PANE_PATH = "/Wardrobe/BoutiqueWhen/then/Body/Preview/PreviewCol/PaneZ/Pane"

local function cameraFor(yawDeg: number): any
	local r = 9
	local rad = math.rad(yawDeg)
	return {
		position = { x = math.sin(rad) * r, y = 2.2, z = -math.cos(rad) * r },
		lookAt = { x = 0, y = 1, z = 0 },
		fov = 40,
	}
end

function Wardrobe.build(LuauUI: any, core: any, deps: any): any
	local UI = LuauUI.UI
	local env = deps.env
	local presenter = deps.presenter

	local scope = core:scope("ref-p5-wardrobe")
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

	-- ── services, images ───────────────────────────────────────────────────
	local services = Services.new({ core = core })
	local provider = LuauUI.newResourceProvider(core, { maxConcurrent = 4, cacheBudget = 64 })
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
	local section = core:signal("boutique")
	local category = core:signal("all")
	local autoRotate = core:signal(true)
	local visible = services.visibleItems(category)

	-- presentation: orbit yaw (throwaway)
	local yaw = core:signal(30)

	-- the first worn-but-unowned item (BuyBar subject), stable category order
	local buySubject = core:memo(function(use)
		local worn = use(services.worn)
		local owned = use(services.owned)
		for _, cat in seedData.categories do
			local id = worn[cat]
			if id ~= nil and owned[id] ~= true then
				return seedData.itemById(id)
			end
		end
		return nil
	end)

	-- ── feedback → sound ids ───────────────────────────────────────────────
	local soundLog: { string } = {}
	local SFX: { [string]: string } = {
		activate = "sfx.wd.tap",
		select = "sfx.wd.flip",
		adjust = "sfx.wd.tick",
		commit = "sfx.wd.done",
		reject = "sfx.wd.deny",
		dismiss = "sfx.wd.close",
		cancel = "sfx.wd.close",
	}
	scope:own(presenter.onFeedback(function(event: any)
		local id = SFX[event.type]
		if id ~= nil then
			table.insert(soundLog, id)
		end
	end))

	-- ── stage wiring (host resolved after present; nil = fallback plate) ───
	local stageAvailable = core:signal(false)
	local stageLog: { any } = {}
	local stageHost: any = nil
	local function pushCamera()
		if stageHost ~= nil then
			stageHost.setCamera(cameraFor(yaw:get()))
		end
		table.insert(stageLog, { camera = yaw:get() })
	end
	local function pushRig()
		local parts = services.rigContent()
		if deps.stage ~= nil then
			deps.stage.apply(PANE_PATH, { parts = parts })
		end
		table.insert(stageLog, { rigParts = #parts })
	end

	-- ── toast helper ───────────────────────────────────────────────────────
	local function toast(textKey: string, param: string?)
		presenter.presentToast(
			UI.VStack({
				id = "ToastPlate",
				surface = "raised",
				padding = "m",
				children = { UI.Text({ id = "Msg", text = L(textKey, param), textSize = "label" }) },
			}),
			{ key = "wardrobe", duration = 4 }
		)
	end

	-- ── purchase modal ─────────────────────────────────────────────────────
	local confirmHandle: any = nil
	local function presentConfirm(item: seedData.Item)
		local pending = core:memo(function(use)
			return use(services.purchaseStatus) == "pending" and use(services.purchasePendingId) == item.id
		end)
		local confirmLabel = core:memo(function(use)
			return if use(pending)
				then strings.get(use(locale), "buy.pending")
				else strings.get(use(locale), "buy.confirm")
		end)
		local buttonsEnabled = core:memo(function(use)
			return not use(pending)
		end)
		local reason = core:memo(function(use)
			local status = use(services.purchaseStatus)
			local r = use(services.purchaseReason)
			if status ~= "rejected" or r == nil then
				return nil
			end
			local param = if r == "err.buy.insufficient" then SPARK .. " " .. tostring(use(services.balance)) else nil
			return strings.get(use(locale), r, param)
		end)
		local handle
		handle = presenter.presentModal(
			UI.Screen({
				id = "Confirm",
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
										width = { type = "minMax", min = 260, max = CONFIRM_W },
										children = {
											UI.Text({ id = "Name", text = item.name, textSize = "heading" }),
											UI.Text({
												id = "Creator",
												text = item.creator,
												textSize = "caption",
												role = "secondary",
											}),
											UI.Text({
												id = "Price",
												text = SPARK .. " " .. tostring(item.price),
												textSize = "numeral",
											}),
											UI.Text({
												id = "After",
												text = core:memo(function(use)
													return strings.get(
														use(locale),
														"buy.after",
														SPARK
															.. " "
															.. tostring(use(services.balance) - (item.price :: number))
													)
												end),
												textSize = "caption",
												role = "secondary",
											}),
											UI.When({
												id = "Reason",
												condition = core:memo(function(use)
													return use(reason) ~= nil
												end),
												thenView = function()
													return UI.Text({
														id = "Strip",
														text = core:memo(function(use)
															return use(reason) or ""
														end),
														tint = { role = "danger", blend = 1 },
													})
												end,
											}),
											UI.HStack({
												id = "Footer",
												gap = "m",
												children = {
													UI.Button({
														id = "Confirm",
														label = confirmLabel,
														surface = "accent",
														enabled = buttonsEnabled,
														onActivate = function()
															services.purchase(item.id)
														end,
													}),
													UI.Button({
														id = "Cancel",
														label = Lnow("buy.cancel"),
														role = "cancel",
														enabled = buttonsEnabled,
														onActivate = function()
															presenter.dismiss(handle)
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
		confirmHandle = handle
	end

	-- track the purchase subject's name for the receipt toast (the service
	-- clears pendingId on resolve, so remember it at command time)
	local lastConfirmedName: string? = nil
	local origPurchase = services.purchase
	services.purchase = function(id: string)
		local item = seedData.itemById(id)
		lastConfirmedName = if item ~= nil then item.name else nil
		origPurchase(id)
	end

	scope:own(core:observe(services.purchaseStatus, function(status: string)
		if status == "confirmed" then
			if confirmHandle ~= nil then
				presenter.dismiss(confirmHandle)
				confirmHandle = nil
			end
			toast("buy.done", lastConfirmedName or "")
		end
	end))

	-- ── refine modal ───────────────────────────────────────────────────────
	local sortSignal = services.sort
	local function presentRefine()
		local picker = LuauUI.newPicker(LuauUI, core, {
			id = "Sort",
			label = Lnow("filter.sort"),
			options = {
				{ value = "featured", label = Lnow("filter.sort.featured") },
				{ value = "price", label = Lnow("filter.sort.price") },
				{ value = "newest", label = Lnow("filter.sort.newest") },
			},
			selected = sortSignal,
			presentation = "automatic",
			sizeClass = conditions.sizeClass,
		})
		local handle
		handle = presenter.presentModal(
			UI.Screen({
				id = "Refine",
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
										width = { type = "minMax", min = 240, max = 360 },
										children = {
											UI.Toggle({
												id = "OwnedOnly",
												label = Lnow("filter.owned"),
												value = services.ownedOnly,
											}),
											picker.blueprint,
											UI.Button({
												id = "Done",
												label = Lnow("filter.done"),
												onActivate = function()
													presenter.dismiss(handle)
													if picker.dispose ~= nil then
														picker.dispose()
													end
												end,
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

	-- ── item card ──────────────────────────────────────────────────────────
	local function itemCard(item: seedData.Item, itemScope: any)
		local img = LuauUI.newAsyncImage(LuauUI, core, {
			id = "Thumb",
			scope = itemScope,
			provider = provider,
			key = item.thumbKey,
			width = { type = "fill", weight = 1 },
			-- FIXED height, deliberately not `aspect` (live matrix 2026-08-09,
			-- xa + parchment + compact): an aspect-on-fill thumb couples the
			-- CELL HEIGHT to the grid's column width, and the Grid's uniform
			-- measure and its arrange can disagree about that width inside an
			-- overflowing scroller (bar reserve) — the Picked plate painted 29px
			-- past its measured box. A width-independent cell height makes
			-- measure and arrange agree by construction; the framework-side
			-- fixed point is framework-fixes.md finding 21. Height matches the
			-- CARD_MIN column floor so the thumb reads square at the floor width.
			height = { type = "fixed", px = CARD_MIN },
		})
		local worn = core:memo(function(use)
			return use(services.worn)[item.category] == item.id
		end)
		local owned = core:memo(function(use)
			return use(services.owned)[item.id] == true
		end)
		local cardEnabled = core:memo(function(use)
			return not (use(services.purchaseStatus) == "pending" and use(services.purchasePendingId) == item.id)
		end)
		local verifiedLabel: any = nil
		if item.verified then
			local vl = LuauUI.newLabel(LuauUI, core, {
				id = "Verified",
				title = Lnow("verified"),
				icon = "wardrobe:verified",
				presentation = "iconOnly",
			})
			if vl.dispose ~= nil then
				itemScope:own(vl.dispose)
			end
			verifiedLabel = vl.blueprint
		end
		local metaChildren: { any } = {
			UI.Text({
				id = "Creator",
				text = item.creator,
				textSize = "caption",
				role = "secondary",
				lineLimit = 1,
				disclose = true,
			}),
		}
		if verifiedLabel ~= nil then
			metaChildren[#metaChildren + 1] = verifiedLabel
		end
		return UI.Button({
			id = item.id,
			label = item.name,
			selected = worn,
			enabled = cardEnabled,
			onActivate = function()
				services.equip(item.id)
			end,
			children = {
				UI.VStack({
					id = "Col",
					gap = "xs",
					align = "stretch",
					children = {
						UI.corners(img.blueprint, "control"),
						UI.Text({
							id = "Name",
							text = item.name,
							textSize = "label",
							lineLimit = 1,
							disclose = true,
						}),
						UI.HStack({ id = "Meta", gap = "xs", children = metaChildren }),
						UI.HStack({
							id = "Status",
							gap = "xs",
							children = {
								UI.When({
									id = "Price",
									condition = core:memo(function(use)
										return item.price ~= nil and not use(owned)
									end),
									thenView = function()
										return UI.Text({
											id = "Pill",
											surface = "chip",
											text = SPARK .. " " .. tostring(item.price),
											textSize = "caption",
										})
									end,
								}),
								UI.When({
									id = "Owned",
									condition = core:memo(function(use)
										return use(owned) and not use(worn)
									end),
									thenView = function()
										return UI.Text({
											id = "Chip",
											surface = "chip",
											text = L("chip.owned"),
											textSize = "caption",
										})
									end,
								}),
								UI.When({
									id = "Wearing",
									condition = worn,
									thenView = function()
										return UI.Text({
											id = "Chip",
											surface = "chip",
											text = L("chip.wearing"),
											textSize = "caption",
										})
									end,
								}),
							},
						}),
					},
				}),
			},
		})
	end

	-- ── catalog region ─────────────────────────────────────────────────────
	local function underlineTint(catId: string)
		local s = clock:spring(if category:get() == catId then 1 else 0, "object")
		scope:own(core:observe(category, function(now: string)
			s:setTarget(if now == catId then 1 else 0)
		end))
		return core:memo(function(use)
			return { role = "accent", blend = use(s) }
		end)
	end

	local categoryButtons: { any } = {}
	for _, cat in seedData.categories do
		local c = cat
		-- underline OVERLAYS the button's bottom edge (matrix row 2026-08-08: a
		-- stacked underline added 8px past the x-scroller's cross axis on every
		-- category — the indicator is paint, so it rides the box instead)
		categoryButtons[#categoryButtons + 1] = UI.ZStack({
			id = "Cat_" .. c,
			children = {
				UI.Button({
					id = "B",
					label = L("cat." .. c),
					selected = core:memo(function(use)
						return use(category) == c
					end),
					onActivate = function()
						category:set(c)
					end,
				}),
				UI.Box({
					id = "Underline",
					height = { type = "fixed", px = 3 },
					width = { type = "fill", weight = 1 },
					alignV = "end",
					tint = underlineTint(c),
				}),
			},
		})
	end

	local pickedSet: { [string]: boolean } = {}
	for _, id in seedData.picked do
		pickedSet[id] = true
	end
	local pickedItems = core:memo(function(use)
		local out: { seedData.Item } = {}
		for _, item in use(visible) :: { seedData.Item } do
			if pickedSet[item.id] then
				out[#out + 1] = item
			end
		end
		return out
	end)
	local restItems = core:memo(function(use)
		local out: { seedData.Item } = {}
		for _, item in use(visible) :: { seedData.Item } do
			if not pickedSet[item.id] then
				out[#out + 1] = item
			end
		end
		return out
	end)
	local nothingMatches = core:memo(function(use)
		return #use(visible) == 0
	end)

	local function itemGrid(id: string, items: any)
		return UI.Grid({
			id = id,
			minColumnWidth = CARD_MIN,
			itemSizing = "uniform",
			gap = "s",
			rowGap = "m",
			children = {
				UI.ForEach({
					id = "Items",
					items = items,
					key = function(item: seedData.Item)
						return item.id
					end,
					row = function(item: seedData.Item, rowScope: any)
						return itemCard(item, rowScope)
					end,
				}),
			},
		})
	end

	local catalogRegion = UI.Region({
		id = "Catalog",
		group = "catalog",
		rank = 2,
		sizing = "fill",
		mayScroll = true,
		floor = { targets = 2 },
		children = {
			UI.VStack({
				id = "CatalogCol",
				gap = "s",
				height = { type = "fill", weight = 1 },
				children = {
					UI.HStack({
						id = "CategoryRow",
						gap = "s",
						-- fill, not hug: a fill-width scroller contributes 0 to a HUG
						-- row's measure (solver seam, framework-fixes ledger
						-- 2026-08-08), and this row should span its lane regardless
						width = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Cats",
								axis = "x",
								gap = "s",
								width = { type = "fill", weight = 1 },
								children = categoryButtons,
							}),
							UI.Button({
								id = "Filter",
								label = Lnow("filter"),
								shape = "circle",
								icon = "wardrobe:filter",
								onActivate = presentRefine,
							}),
						},
					}),
					UI.ScrollView({
						id = "Items",
						gap = "m",
						height = { type = "fill", weight = 1 },
						children = {
							UI.When({
								id = "EmptyWhen",
								condition = nothingMatches,
								thenView = function()
									return UI.VStack({
										id = "Empty",
										gap = "s",
										align = "center",
										children = {
											UI.Text({
												id = "H",
												text = L("filter.none"),
												textSize = "heading",
											}),
											UI.Button({
												id = "Reset",
												label = Lnow("filter.reset"),
												onActivate = function()
													services.ownedOnly:set(false)
													services.sort:set("featured")
													category:set("all")
												end,
											}),
										},
									})
								end,
							}),
							UI.When({
								id = "PickedWhen",
								condition = core:memo(function(use)
									return #use(pickedItems) > 0
								end),
								thenView = function()
									return UI.VStack({
										id = "Picked",
										gap = "s",
										children = {
											UI.Text({
												id = "H",
												text = L("picked.header"),
												textSize = "heading",
											}),
											itemGrid("PickedGrid", pickedItems),
										},
									})
								end,
							}),
							UI.When({
								id = "RestWhen",
								condition = core:memo(function(use)
									return #use(restItems) > 0
								end),
								thenView = function()
									return UI.VStack({
										id = "Rest",
										gap = "s",
										children = {
											UI.Text({
												id = "H",
												text = L("everything.header"),
												textSize = "heading",
											}),
											itemGrid("RestGrid", restItems),
										},
									})
								end,
							}),
						},
					}),
				},
			}),
		},
	})

	-- ── preview region ─────────────────────────────────────────────────────
	local orbitState: { lastX: number? } = { lastX = nil }
	local orbitGrip = UI.Grip({
		id = "Orbit",
		focusable = true,
		focusVisual = "none",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		onPointerDown = function(_path: string, pos: any)
			orbitState.lastX = pos.x
			return true
		end,
		onPointerMove = function(_path: string, pos: any)
			if orbitState.lastX ~= nil then
				yaw:set((yaw:get() + (pos.x - (orbitState.lastX :: number)) * 0.6) % 360)
				orbitState.lastX = pos.x
			end
		end,
		onPointerUp = function()
			orbitState.lastX = nil
		end,
		onPointerCancel = function()
			orbitState.lastX = nil
		end,
	})

	local orbitWithAdjust = LuauUI.contribution.attach(orbitGrip, {
		adjustTargets = function(rootNode: any): { [string]: boolean }
			return { [rootNode.path] = true }
		end,
		handleAdjust = function(_path: string, direction: number): boolean
			yaw:set((yaw:get() + direction * 30) % 360)
			return true
		end,
		adjustAxis = "horizontal",
	})

	local previewRegion = UI.Region({
		id = "Preview",
		group = "preview",
		rank = 1,
		sizing = "fill",
		floor = { targets = 2 },
		children = {
			UI.VStack({
				id = "PreviewCol",
				gap = "xs",
				height = { type = "fill", weight = 1 },
				children = {
					UI.ZStack({
						id = "PaneZ",
						-- FILL, deliberately: the pane absorbs the column's slack and
						-- YIELDS it back when the purchase bar mounts. The earlier
						-- `minMax` preferred here could not — a `minMax` with a
						-- `preferred` never consults the offer and a flow stack has no
						-- compress step, so the parchment-metrics BuyBar pushed the
						-- column 23px past its box (live matrix, 2026-08-08; recorded
						-- as the flex-shrink follow-on proposal in framework-fixes.md).
						-- The pane's visual minimum is the Region floor's job, not
						-- this node's.
						height = { type = "fill", weight = 1 },
						children = {
							UI.stroke(
								UI.Stage({
									id = "Pane",
									surface = "raised",
									width = { type = "fill", weight = 1 },
									height = { type = "fill", weight = 1 },
								}),
								{ color = "accent" }
							),
							orbitWithAdjust,
							UI.When({
								id = "FallbackWhen",
								condition = core:memo(function(use)
									return not use(stageAvailable)
								end),
								thenView = function()
									return UI.VStack({
										id = "Fallback",
										gap = "s",
										align = "center",
										padding = "m",
										children = {
											UI.Text({
												id = "Cap",
												text = L("preview.unavailable"),
												textSize = "caption",
												role = "secondary",
											}),
											--[[ A WRAPPING ROW (parity round 3), not the bare `ForEach`
												this used to be. A `ForEach` whose parent is this `VStack`
												gave every worn piece A LINE OF ITS OWN: four equipped
												categories burned four stacked lines of a fallback plate that
												is already competing with the preview pane for height, and
												the names are short words ("Cap", "Visor").

												This is also the case that could not be hand-built. A
												`ForEach` row returns exactly ONE blueprint, so no separator
												could ever be interleaved on the parent's main axis, and the
												count is variable (it follows what the mannequin is wearing).
												`wrap` + `distribute` on the CONTAINER is the only spelling
												that reaches a variable-count list. ]]
											UI.HStack({
												id = "WornRow",
												wrap = true,
												gap = "xs",
												distribute = "center",
												width = { type = "fill", weight = 1 },
												children = {
													UI.ForEach({
														id = "WornChips",
														items = core:memo(function(use)
															local out: { seedData.Item } = {}
															local worn = use(services.worn)
															for _, cat in seedData.categories do
																local id = worn[cat]
																if id ~= nil then
																	local item = seedData.itemById(id)
																	if item ~= nil then
																		out[#out + 1] = item
																	end
																end
															end
															return out
														end),
														key = function(item: seedData.Item)
															return item.id
														end,
														row = function(item: seedData.Item)
															return UI.Text({
																id = "Chip",
																surface = "chip",
																text = item.name,
																textSize = "caption",
															})
														end,
													}),
												},
											}),
										},
									})
								end,
							}),
							UI.VStack({
								id = "Controls",
								alignH = "start",
								alignV = "end",
								gap = "xs",
								padding = "s",
								children = {
									UI.Toggle({
										id = "Spin",
										label = Lnow("preview.autorotate"),
										value = autoRotate,
									}),
									UI.HStack({
										id = "History",
										gap = "xs",
										children = {
											UI.Button({
												id = "Undo",
												label = Lnow("undo"),
												shape = "circle",
												icon = "wardrobe:undo",
												enabled = services.canUndo,
												onActivate = function()
													services.undo()
												end,
											}),
											UI.Button({
												id = "Redo",
												label = Lnow("redo"),
												shape = "circle",
												icon = "wardrobe:redo",
												enabled = services.canRedo,
												onActivate = function()
													services.redo()
												end,
											}),
										},
									}),
								},
							}),
						},
					}),
					UI.When({
						id = "BuyBarWhen",
						condition = core:memo(function(use)
							return use(buySubject) ~= nil
						end),
						transition = { enter = "slide-up" },
						thenView = function()
							return UI.VStack({
								id = "BuyBar",
								--[[ NO `alignV` HERE. It used to say `"end"` — "sit at the bottom" —
									but this bar splices into `PreviewCol`, a VSTACK, whose MAIN axis is Y.
									A stack reads no `alignV` off a child at all, and even the cross-axis
									spelling (`lineAlign`) is the wrong axis for this request, so it was
									accepted and then ignored (§2.1 placement audit, 2026-08-13).

									MEASURED BEFORE DELETING: `PreviewCol` solves to y 54..900 and this bar to
									y 854..900, so the bar is ALREADY flush with the column's bottom edge (the
									preview above it fills, leaving no main-axis slack). The prop was redundant
									rather than a latent bug, and deleting it moves nothing — recorded under
									"no queue entry needed" in
									`docs/plans/unfulfilled-placement-intents.md`. ]]
								children = {
									UI.Button({
										id = "Buy",
										label = core:memo(function(use)
											local item = use(buySubject)
											if item == nil then
												return ""
											end
											return strings.get(use(locale), "buy.cta", item.name)
												.. "  —  "
												.. SPARK
												.. " "
												.. tostring(item.price)
										end),
										surface = "accent",
										onActivate = function()
											local item = buySubject:get()
											if item ~= nil then
												presentConfirm(item)
											end
										end,
									}),
								},
							})
						end,
					}),
				},
			}),
		},
	})

	-- ── chrome (segments + wallet) ─────────────────────────────────────────
	local sectionPicker = LuauUI.newPicker(LuauUI, core, {
		id = "Section",
		options = {
			{ value = "boutique", label = Lnow("section.boutique") },
			{ value = "outfits", label = Lnow("section.outfits") },
			{ value = "profile", label = Lnow("section.profile") },
		},
		selected = section,
		presentation = "automatic",
		sizeClass = conditions.sizeClass,
	})
	if sectionPicker.dispose ~= nil then
		scope:own(sectionPicker.dispose)
	end

	local walletCounter = clock:counter(services.balance:get(), "reward")
	scope:own(core:observe(services.balance, function(v: number)
		walletCounter:setTarget(v)
	end))

	-- one wallet pill, two homes: the chrome row (regular+) and a pane-corner
	-- chip (compact — matrix row 2026-08-08: three 8-char picker segments plus
	-- the wallet cannot share 360px; the picker keeps the row, the wallet rides
	-- the pane, and the fact stays visible in both arrangements per spec §6.5)
	local function walletPill(id: string)
		return UI.HStack({
			id = id,
			gap = "xs",
			children = {
				UI.Text({ id = "Mark", text = SPARK, textSize = "label" }),
				UI.Text({
					id = "Amount",
					textSize = "numeral",
					text = core:memo(function(use)
						return tostring(use(walletCounter))
					end),
				}),
			},
		})
	end

	local chromeRegion = UI.Region({
		id = "Segments",
		group = "chrome",
		rank = 3,
		children = {
			UI.HStack({
				id = "ChromeRow",
				gap = "m",
				width = { type = "fill", weight = 1 },
				children = {
					sectionPicker.blueprint,
					UI.When({
						id = "WalletWhen",
						condition = core:memo(function(use)
							return not use(conditions.isCompact)
						end),
						thenView = function()
							return walletPill("Wallet")
						end,
					}),
				},
			}),
		},
	})
	-- ── stub sections ──────────────────────────────────────────────────────
	local function stubPlate(nameKey: string)
		return UI.VStack({
			id = "Stub",
			gap = "s",
			align = "center",
			height = { type = "fill", weight = 1 },
			children = {
				UI.Text({ id = "Name", text = L(nameKey), textSize = "heading" }),
				UI.Text({ id = "Body", text = L("stub.body") }),
				UI.Text({ id = "Honest", text = L("stub.honest"), textSize = "caption", role = "secondary" }),
			},
		})
	end

	-- ── screen ─────────────────────────────────────────────────────────────
	local screen = UI.Screen({
		id = "Wardrobe",
		gap = "m",
		children = {
			UI.When({
				id = "BoutiqueWhen",
				condition = core:memo(function(use)
					return use(section) == "boutique"
				end),
				thenView = function()
					return UI.Composition({
						id = "Body",
						height = { type = "fill", weight = 1 },
						arrangements = {
							{ name = "split", lanes = { { "main" }, { "trail" } } },
							{ name = "stacked", lanes = { { "trail", "main" } } },
						},
						laneGap = "m",
						groupGap = "s",
						groups = {
							{ id = "chrome", span = "above" },
							-- both lanes fill with floors: a box that cannot afford
							-- catalogMin + previewMin makes `split` illegal and the
							-- stacked fallback wins — the lane floor, never a device
							-- name, decides the arrangement (spec §7)
							{ id = "catalog", lane = "main", sizing = "fill", weight = 1.2, minWidth = 300 },
							{
								id = "preview",
								lane = "trail",
								sizing = "fill",
								weight = 1,
								minWidth = PREVIEW_LANE_MIN,
							},
						},
						children = { chromeRegion, previewRegion, catalogRegion },
					})
				end,
			}),
			UI.When({
				id = "OutfitsWhen",
				condition = core:memo(function(use)
					return use(section) == "outfits"
				end),
				thenView = function()
					return stubPlate("section.outfits")
				end,
			}),
			UI.When({
				id = "ProfileWhen",
				condition = core:memo(function(use)
					return use(section) == "profile"
				end),
				thenView = function()
					return stubPlate("section.profile")
				end,
			}),
		},
	})

	-- ── present (self-presenting: the proof owns the controller) ───────────
	local handle = presenter.present(screen, {
		keyboardNavigation = true,
		initialFocus = "first",
	})
	presenter.refresh()

	-- resolve the stage host through the PUBLIC controller; nil = fallback
	local paneStagePath: string? = nil
	do
		local controller = (handle :: any).controller
		if controller ~= nil and controller.stageHost ~= nil then
			-- the Composition's When wrapper prefixes the authored path; resolve
			-- the real mounted path by suffix through the adapter-agnostic dump
			-- of stage candidates: try authored path first, then discovery
			local host = controller.stageHost(PANE_PATH)
			if host ~= nil then
				paneStagePath = PANE_PATH
			end
			if host == nil and deps.adapter ~= nil and (deps.adapter :: any).paths ~= nil then
				for _, path in (deps.adapter :: any).paths() do
					if string.find(path, "/PaneZ/Pane", 1, true) ~= nil then
						host = controller.stageHost(path)
						if host ~= nil then
							paneStagePath = path
							break
						end
					end
				end
			end
			stageHost = host
		end
	end
	stageAvailable:set(stageHost ~= nil)
	presenter.refresh()
	if stageHost ~= nil then
		stageHost.setLighting({
			ambient = { r = 0.55, g = 0.55, b = 0.58 },
			lightColor = { r = 1, g = 0.98, b = 0.94 },
			lightDirection = { x = -1, y = -2, z = -1 },
		})
		pushCamera()
	end
	pushRig()

	-- live re-dress + orbit + turntable
	scope:own(core:observe(services.worn, function()
		pushRig()
	end))
	scope:own(core:observe(yaw, function()
		pushCamera()
	end))
	scope:own(presenter.onTick(function(dt: number)
		settleImages()
		local reduced = env:get("reducedMotion") == true
		if autoRotate:get() and not reduced then
			yaw:set((yaw:get() + dt * 12) % 360)
		end
	end))

	local steps = {
		locale = function(_built: any, value: string?)
			locale:set(if value == "xa" then "xa" else "en")
		end,
		section = function(_built: any, value: string?)
			if value ~= nil then
				section:set(value)
			end
		end,
		category = function(_built: any, value: string?)
			if value ~= nil then
				category:set(value)
			end
		end,
		equip = function(_built: any, id: string?)
			if id ~= nil then
				services.equip(id)
			end
			-- returned so the scenario step log carries the post-command truth
			return { worn = services.worn:get(), id = id, itemKnown = seedData.itemById(id or "") ~= nil }
		end,
		undo = function()
			services.undo()
		end,
		redo = function()
			services.redo()
		end,
		settle = function()
			services.settle()
		end,
		settleImages = settleImages,
		yaw = function(_built: any, value: number?)
			if value ~= nil then
				yaw:set(value % 360)
			end
		end,
	}

	return {
		handle = handle,
		screen = screen,
		steps = steps,
		stageContent = {
			[paneStagePath or PANE_PATH] = {
				camera = cameraFor(yaw:get()),
				lighting = {
					ambient = { r = 0.55, g = 0.55, b = 0.58 },
					lightColor = { r = 1, g = 0.98, b = 0.94 },
					lightDirection = { x = -1, y = -2, z = -1 },
				},
				parts = services.rigContent(),
			},
		},
		report = function()
			local undoDepth, redoDepth = services.historyDepths()
			return {
				proof = "p5_wardrobe",
				section = section:get(),
				category = category:get(),
				worn = services.worn:get(),
				balance = services.balance:get(),
				purchaseStatus = services.purchaseStatus:get(),
				undoDepth = undoDepth,
				redoDepth = redoDepth,
				stageAvailable = stageAvailable:get(),
				stagePath = paneStagePath,
				yaw = yaw:get(),
				soundLog = soundLog,
				stageLog = stageLog,
			}
		end,
		dispose = function()
			scope:dispose()
		end,
		_internals = {
			services = services,
			provider = provider,
			signals = { section = section, category = category, yaw = yaw, locale = locale },
			buySubject = buySubject,
			stageHostRef = function()
				return stageHost
			end,
		},
	}
end

return Wardrobe
