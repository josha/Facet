--!strict
-- WORKBENCH — the potion editor (spec §9).
--
-- LIVE-BOUND, NO SAVE. Every edit writes the potion's signals immediately, so
-- the preview and the six gauges move on the same frame as the picker. There is
-- no Save control to explain and no discard prompt to write, because there is
-- nothing uncommitted to lose — the header says so in one line.
--
-- THE GAUGES ARE RELATIVE-MAX (reference behavior): each bar is that attribute
-- against the STRONGEST attribute of this potion, so the shape of a recipe reads
-- at a glance instead of six bars all near empty. `newProgressView.max` is not a
-- reactive prop, so the ratio is computed in the memo and the control runs 0..1
-- — same picture, one authority.
local data = require("../content/data")
local parts = require("./parts")

local workbench = {}

local SCRATCH = "scratch"
-- the picker option id for an empty optional slot. A real id rather than an
-- empty string: an option id is a path segment, and a path segment cannot be
-- nothing.
local NONE = "none"

function workbench.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local Facet = app.Facet

	local self: any = {}

	-- ---- the edit store ------------------------------------------------------
	-- One record per potion (plus the shared scratch draft), so switching away
	-- and back keeps an edit — the same thing the service would do in a real
	-- game, kept client-side here because a scratch potion is never saved.
	local store: { [string]: any } = {}
	local function recordFor(id: string): any
		local existing = store[id]
		if existing ~= nil then
			return existing
		end
		local potion = data.potionById(id)
		local record = if potion ~= nil
			then {
				name = potion.name,
				base = potion.base,
				essence = potion.essence or NONE,
				garnish = potion.garnish or NONE,
			}
			else { name = S.t("bench.draft"), base = "springwater", essence = NONE, garnish = NONE }
		store[id] = record
		return record
	end
	self.recordFor = recordFor

	local currentId = core:memo(function(use)
		local open = use(app.state.openPotion)
		if open ~= "" then
			return open
		end
		return SCRATCH
	end)
	self.currentId = currentId

	-- the four live signals the controls own; `loading` guards the write-back so
	-- a load cannot be mistaken for an edit
	local nameValue = core:signal("")
	local baseValue = core:signal("springwater")
	local essenceValue = core:signal(NONE)
	local garnishValue = core:signal(NONE)
	local loading = false

	local function load(id: string)
		local record = recordFor(id)
		loading = true
		nameValue:set(record.name)
		baseValue:set(record.base)
		essenceValue:set(record.essence)
		garnishValue:set(record.garnish)
		loading = false
	end

	local function save()
		if loading then
			return
		end
		local record = recordFor(currentId:get())
		record.name = nameValue:get()
		record.base = baseValue:get()
		record.essence = essenceValue:get()
		record.garnish = garnishValue:get()
	end

	load(currentId:get())
	local unsubscribes = {
		core:observe(currentId, load),
		core:observe(nameValue, save),
		core:observe(baseValue, save),
		core:observe(essenceValue, save),
		core:observe(garnishValue, save),
	}

	-- ---- the derived recipe --------------------------------------------------

	local attributes = core:memo(function(use)
		local essence = use(essenceValue)
		local garnish = use(garnishValue)
		return data.attributesOf(
			use(baseValue),
			if essence == NONE then nil else essence,
			if garnish == NONE then nil else garnish
		)
	end)
	self.attributes = attributes

	local strongest = core:memo(function(use)
		return data.strongestAxis(use(attributes) :: any)
	end)
	self.strongest = strongest

	local peak = core:memo(function(use)
		local attrs = use(attributes) :: any
		return math.max(1, attrs[use(strongest)])
	end)

	-- ---- the live preview ----------------------------------------------------

	local baseHue = core:memo(function(use)
		return { direct = data.baseHueFor(use(baseValue)) }
	end)
	local hasEssence = core:memo(function(use)
		return use(essenceValue) ~= NONE
	end)
	local hasGarnish = core:memo(function(use)
		return use(garnishValue) ~= NONE
	end)

	local function previewPlate(id: string, box: any): any
		return parts.plate(app, {
			id = id,
			align = "center",
			gap = "s",
			children = {
				UI.ZStack({
					id = "Layers",
					width = UI.fill(),
					height = box,
					children = {
						UI.Image({
							id = "Bottle",
							image = app.art.marks.menu.image,
							scaleMode = "fit",
							tint = { role = "contentSecondary", blend = 0.9 },
							width = UI.fill(),
							height = UI.fill(),
						}),
						UI.Image({
							id = "Base",
							image = app.art.marks.chevronUp.image,
							scaleMode = "fit",
							tint = baseHue,
							width = UI.fill(),
							height = UI.fill(),
						}),
						UI.When({
							id = "EssenceWhen",
							condition = hasEssence,
							thenView = function()
								return UI.Image({
									id = "Essence",
									image = app.art.marks.check.image,
									scaleMode = "fit",
									tint = { role = "accent", blend = 0.8 },
									width = UI.fill(),
									height = UI.fill(),
								})
							end,
						}),
						UI.When({
							id = "GarnishWhen",
							condition = hasGarnish,
							thenView = function()
								return UI.Image({
									id = "Garnish",
									image = app.art.marks.more.image,
									scaleMode = "fit",
									tint = { role = "contentStrong", blend = 1 },
									width = UI.fill(),
									height = UI.fill(),
								})
							end,
						}),
					},
				}),
				-- THE CAPTION IS NEVER WIDER THAN THE BOX IT CAPTIONS. `lineLimit`
				-- caps the lines a text spends, never the width it asks for, and
				-- the preview sits in a HUG lane — so a long potion name measured
				-- 401px of single line, the lane hugged all of it, and the form
				-- lane beside it was left 38px on a landscape phone (every
				-- attribute row then reported its own overflow, which is how this
				-- was found). Capping the ask is what makes `lineLimit` bite.
				UI.Text({
					id = "Caption",
					text = nameValue,
					textSize = "heading",
					textAlign = "center",
					width = { type = "minMax", max = "app.cartwheel.previewMin" },
					lineLimit = 2,
					disclose = true,
				}),
			},
		})
	end

	-- TWO FORMS, richest first. A landscape phone gives this composition 221px of
	-- height and the full preview alone wants more than that, so the region steps
	-- DOWN to a thumbnail-sized plate before anything is dropped — which is the
	-- composition's own ladder, not a device branch.
	local preview = previewPlate("Preview", { type = "fixed", px = "app.cartwheel.previewMin" })
	local previewCompact = previewPlate("PreviewCompact", { type = "fixed", px = "controls.image.defaultSize" })

	-- ---- the form ------------------------------------------------------------

	local nameField = Facet.Controls.TextInput(core, {
		id = "Name",
		value = nameValue,
		placeholder = S.t("bench.name"),
		maxLength = 24,
		-- an IDEMPOTENT normalizer: trim, and never anything a second pass would
		-- change (the engine echoes a programmatic write back through the seam)
		validate = function(proposed: string): string?
			return (string.gsub(proposed, "^%s*(.-)%s*$", "%1"))
		end,
		clearButtonMode = "whileEditing",
		env = app.env,
		actionSystem = app.actionSystem,
	})

	local gauges: { any } = {}
	local gaugeMemos: { any } = {}
	local attributeRows: { any } = {}
	for axis = 1, 6 do
		local ratio = core:memo(function(use)
			local attrs = use(attributes) :: any
			return math.clamp(attrs[axis] / use(peak), 0, 1)
		end)
		table.insert(gaugeMemos, ratio)
		local gauge = Facet.Controls.ProgressView(core, {
			id = "Gauge" .. axis,
			value = ratio,
			min = 0,
			max = 1,
		})
		table.insert(gauges, gauge)
		local isStrongest = core:memo(function(use)
			return use(strongest) == axis
		end)
		table.insert(gaugeMemos, isStrongest)
		local roleMemo = core:memo(function(use)
			return if use(isStrongest) then "content" else "secondary"
		end)
		table.insert(gaugeMemos, roleMemo)
		local valueText = core:memo(function(use)
			return tostring((use(attributes) :: any)[axis])
		end)
		table.insert(gaugeMemos, valueText)
		local tintMemo = core:memo(function(use)
			return { role = "accent", blend = if use(isStrongest) then 1 else 0.25 }
		end)
		table.insert(gaugeMemos, tintMemo)
		table.insert(
			attributeRows,
			UI.HStack({
				id = "Attr" .. axis,
				-- the tightest legal gap: the row carries an icon, a name, a gauge
				-- and a numeral, and at a landscape phone's form width the wider
				-- step spent exactly the 12px it overflowed by
				gap = "xs",
				align = "center",
				width = UI.fill(),
				children = {
					UI.Image({
						id = "Mark",
						image = app.art.markFor(axis).image,
						scaleMode = "fit",
						tint = tintMemo,
						width = { type = "fixed", px = "iconSizes.small" },
						height = { type = "fixed", px = "iconSizes.small" },
					}),
					-- BOTH shrink, in proportion: a natural-width label beside a
					-- fill bar overflowed the row by 56px once the form was a column
					-- on a landscape phone
					UI.Text({
						id = "Name",
						text = parts.attributeName(app, axis),
						textSize = "label",
						role = roleMemo,
						width = UI.fill(),
						lineLimit = 1,
						disclose = true,
					}),
					UI.VStack({
						id = "Bar",
						width = UI.fill(2),
						children = { gauge.blueprint },
					}),
					UI.Text({ id = "Value", text = valueText, textSize = "numeral", role = roleMemo }),
				},
			})
		)
	end

	local function ingredientOptions(list: { any }, withNone: boolean): { any }
		local options: { any } = {}
		if withNone then
			table.insert(options, { id = NONE, label = S.t("bench.none") })
		end
		for _, entry in list do
			table.insert(options, { id = entry.id, label = entry.name })
		end
		return options
	end

	--[[ THE THREE INGREDIENT PICKERS NOW ADAPT WITHOUT BEING TOLD ANYTHING
		(ADAPT-1, 2026-08-18). All three wired `sizeClass` and none wired
		`interactionClasses`, which is why every one of them presented a floating
		plate on a phone — the audit's exact words — where the reference platform's
		default is a bottom sheet. `presentation = "automatic"` stays because it is
		the interesting declaration: this control ASKS to adapt, and the facts come
		from the surface it is standing on. ]]
	local basePicker = Facet.Controls.PopupButton(core, {
		id = "Base",
		options = ingredientOptions(data.bases :: any, false),
		value = baseValue,
		presentation = "automatic",
	})
	local essencePicker = Facet.Controls.PopupButton(core, {
		id = "Essence",
		options = ingredientOptions(data.essences :: any, true),
		value = essenceValue,
		presentation = "automatic",
	})
	local garnishPicker = Facet.Controls.PopupButton(core, {
		id = "Garnish",
		options = ingredientOptions(data.garnishes :: any, true),
		value = garnishValue,
		presentation = "automatic",
	})

	-- the three pickers, reachable by name: `api.select(id)` is the control's own
	-- public drive verb, so a scenario step and a test press the same control a
	-- finger does rather than writing the signal behind it
	self.pickers = { base = basePicker, essence = essencePicker, garnish = garnishPicker }
	self.nameField = nameField
	self.nameValue = nameValue

	local form = UI.ScrollView({
		id = "Form",
		axis = "y",
		gap = "m",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			UI.VStack({
				id = "Potion",
				gap = "xs",
				width = UI.fill(),
				children = {
					UI.Text({ id = "Heading", text = S.t("bench.sectionPotion"), textSize = "heading" }),
					nameField.blueprint,
				},
			}),
			UI.VStack({
				id = "Attributes",
				gap = "xs",
				width = UI.fill(),
				children = {
					UI.Text({ id = "Heading", text = S.t("bench.sectionAttributes"), textSize = "heading" }),
					UI.VStack({
						id = "Rows",
						gap = "xs",
						width = UI.fill(),
						children = attributeRows,
					}),
				},
			}),
			UI.VStack({
				id = "Ingredients",
				gap = "xs",
				width = UI.fill(),
				children = {
					UI.Text({ id = "Heading", text = S.t("bench.sectionIngredients"), textSize = "heading" }),
					UI.HStack({
						id = "BaseRow",
						gap = "s",
						align = "center",
						children = {
							-- the LABEL shrinks, not the picker: a picker's trigger is
							-- as wide as its longest option ("Ribbon · Coppertonic")
							-- and a fixed-width label beside one overflows a narrow
							-- form
							UI.Text({
								id = "Label",
								text = S.t("bench.base"),
								textSize = "label",
								width = UI.fill(),
								lineLimit = 1,
								disclose = true,
							}),
							basePicker.blueprint,
						},
					}),
					UI.HStack({
						id = "EssenceRow",
						gap = "s",
						align = "center",
						children = {
							-- the LABEL shrinks, not the picker: a picker's trigger is
							-- as wide as its longest option ("Ribbon · Coppertonic")
							-- and a fixed-width label beside one overflows a narrow
							-- form
							UI.Text({
								id = "Label",
								text = S.t("bench.essence"),
								textSize = "label",
								width = UI.fill(),
								lineLimit = 1,
								disclose = true,
							}),
							essencePicker.blueprint,
						},
					}),
					UI.HStack({
						id = "GarnishRow",
						gap = "s",
						align = "center",
						children = {
							-- the LABEL shrinks, not the picker: a picker's trigger is
							-- as wide as its longest option ("Ribbon · Coppertonic")
							-- and a fixed-width label beside one overflows a narrow
							-- form
							UI.Text({
								id = "Label",
								text = S.t("bench.garnish"),
								textSize = "label",
								width = UI.fill(),
								lineLimit = 1,
								disclose = true,
							}),
							garnishPicker.blueprint,
						},
					}),
				},
			}),
		},
	})

	local page = UI.VStack({
		id = "Workbench",
		padding = "m",
		gap = "s",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			UI.Text({ id = "Title", text = S.t("bench.title"), textSize = "title" }),
			UI.Text({ id = "Live", text = S.t("bench.live"), textSize = "caption", role = "secondary" }),
			UI.Composition({
				id = "Bench",
				-- `leadFirst` (framework-gaps-phase2 item 12): see shell.luau's header
				-- for the full account of why this used to be a CUSTOM arrangement
				-- reusing the `"twoLane"` name for different lanes.
				arrangements = { "leadFirst", "column" },
				laneGap = "m",
				groupGap = "m",
				width = UI.fill(),
				height = UI.fill(),
				groups = {
					{ id = "preview", lane = "lead", sizing = "hug", minWidth = "app.cartwheel.previewMin" },
					{ id = "form", lane = "main", sizing = "fill" },
				},
				children = {
					UI.Region({
						id = "Preview",
						group = "preview",
						rank = 2,
						-- the compact preview drops the attribute read-out, and a dropped one
						-- drops the potion entirely — the screen owes both a route
						recover = "overflow",
						floor = { lines = 2 },
						mayDrop = true,
						children = { preview, previewCompact },
					}),
					UI.Region({
						id = "Form",
						group = "form",
						rank = 1,
						sizing = "fill",
						mayScroll = true,
						floor = { lines = 4 },
						children = { form },
					}),
				},
			}),
		},
	})

	function self.view(): any
		return page
	end

	function self.dump(): any
		local attrs = attributes:get() :: any
		return {
			potion = currentId:get(),
			name = nameValue:get(),
			base = baseValue:get(),
			essence = essenceValue:get(),
			garnish = garnishValue:get(),
			attributes = table.clone(attrs),
			strongest = (data.ATTRIBUTES :: any)[strongest:get()],
		}
	end

	function self.dispose()
		for _, unsubscribe in unsubscribes do
			unsubscribe()
		end
		garnishPicker.dispose()
		essencePicker.dispose()
		basePicker.dispose()
		nameField.dispose()
		for _, gauge in gauges do
			gauge.dispose()
		end
		for _, memo in gaugeMemos do
			memo:dispose()
		end
		hasGarnish:dispose()
		hasEssence:dispose()
		baseHue:dispose()
		peak:dispose()
		strongest:dispose()
		attributes:dispose()
		currentId:dispose()
		garnishValue:dispose()
		essenceValue:dispose()
		baseValue:dispose()
		nameValue:dispose()
	end

	return self
end

return workbench
