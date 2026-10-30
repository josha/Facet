--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Double = require("./live_double")

local SUITES: { { id: string, cases: { string } } } = {
	{
		id = "classb_collections",
		cases = {
			"cell-insets-and-header-contrast",
			"drag-across-rows-after-page-scroll",
			"page-scroll-moves-the-table-body",
			"partial-lines-crop-and-offsets-clamp",
			"plate-decoration-stays-inside-the-band",
		},
	},
	{
		id = "classb_examples",
		cases = {
			"card-rail-height-includes-scrollbar-band",
			"confirm-dialog-card-centred",
			"consumer-blurb-grows-with-text-size",
			"outpost-terminal-holds-canvas-every-text-size",
			"settings-sync-compact-phone-every-text-size",
			"word-keyboard-large-text-fits",
		},
	},
	{
		id = "classb_keyboard",
		cases = {
			"circle-corner-wins-in-every-package",
			"clear-button-trailing-and-centred",
			"role-fills-win-at-rest",
			"slider-rest-idle-resize-clearance",
		},
	},
	{
		id = "classb_navigation",
		cases = {
			"collapsible-safe-edges",
			"navigation-back-pointer",
			"navigation-gameplay-lifetime",
			"pageview-fixed-in-scroller",
			"path-clipped-in-scroll",
			"segment-corner-concentric",
			"segment-fill-follows-track",
			"tab-content-stretches-page",
			"tab-reorder-keeps-page-geometry",
			"underline-follows-rehomed-strip",
		},
	},
	{
		id = "classb_themes",
		cases = {
			"authored-metric-native-stroke",
			"selection-corners-follow-control",
			"skeleton-band-contained",
			"skeleton-circle-round-sweep",
			"skeleton-parent-alignment",
			"skinned-selection-hugs-art",
			"status-round-containment",
		},
	},
	{
		id = "focus_probe",
		cases = {
			"F11-selection-image-part",
			"F9-arrow-keys-drive-engine",
		},
	},
	{
		id = "frame_stability",
		cases = {
			"native-indeterminate-progress-layout",
			"native-scroll-change-starts-a-new-state",
			"native-text-change-starts-a-new-state",
			"native-visibility-change-starts-a-new-state",
			"negative-gradient-mask-does-not-hide-a-late-visible-resize",
			"negative-indeterminate-progress-layout-resize",
			"negative-late-resize-after-explicit-state-change",
			"negative-late-resize-after-scroll-change",
			"negative-late-resize-after-text-change",
			"negative-late-resize-after-visibility-change",
			"negative-native-sample-errors-fail-the-observation",
			"negative-one-frame-late-resize",
		},
	},
	{
		id = "gallery",
		cases = {
			"collection-toolbar-in-gallery",
			"collection-toolbar-variants",
			"word-game-fits-the-phone",
		},
	},
	{
		id = "in24",
		cases = {
			"component-setup-error-and-throwing-cleanup",
			"compose-delivery-order",
			"feedback-motion-is-paint-only",
			"image-scale-mode-renders",
			"presence-retires-until-exit",
			"radial-lift-is-paint-only",
			"ring-geometry-only-on-real-change",
			"sheet-reserves-card-feedback-clearance",
			"stack-pop-retires-until-motion-ends",
			"touch-hint-with-no-touch-binding",
			"touch-match3-detector-tap-selects-once",
			"touch-page-view-dots",
		},
	},
	{
		id = "in47",
		cases = {
			"actions-released-with-their-owner",
			"hover-follows-the-pointer",
			"one-action-many-devices",
			"temperature-pointer-enters-edit",
			"touch-one-action-many-devices",
			"touch-slider-drag",
		},
	},
	{
		id = "layout_geometry",
		cases = {
			"callout-edge-gap-shift-clamp",
			"callout-tail-centre-border-corners",
			"chrome-zero-inset-full-bleed",
			"circle-button-authored-axes",
			"circular-progress-stroke-inside-box",
			"grid-cell-width-arithmetic",
			"hud-goals-card-fits-every-device",
			"image-button-caption-clear-of-artwork",
			"image-button-wrapped-cells-reserve-full-height",
			"layers-hang-outside-layout",
			"navigation-stack-root-box-and-back-chrome",
			"panel-insets-reserve-native-padding",
			"popover-themed-arrows-keep-the-frame-unclipped",
			"progress-short-end-label-keeps-its-text",
			"tab-head-accessory-above-rail",
			"vertical-segments-stack-share-width-floor",
		},
	},
	{
		id = "live_bugs",
		cases = {
			"range-knobs-flush",
		},
	},
	{
		id = "motion_continuity",
		cases = {
			"clipping-checker-rejects-label-and-canvasgroup-overflow",
		},
	},
	{
		id = "native_mechanisms",
		cases = {
			"grid-hugs-its-lines",
			"native-fixture-preserves-xml-codec",
			"sibling-order-and-hit-testing",
		},
	},
	{
		id = "native_mechanisms_input",
		cases = {
			"held-button-destruction-cancels",
		},
	},
	{
		id = "navigation_split_view",
		cases = {
			"geometry-feedback",
		},
	},
	{
		id = "needs_live",
		cases = {
			"circular-value-inside-gauge",
			"collapsed-column-details-target",
		},
	},
	{
		id = "needs_live_b",
		cases = {
			"alert-actions-inside-card",
			"disclosure-description-header",
			"playlist-and-grid-panes",
			"progress-skin-under-scale",
		},
	},
	{
		id = "needs_live_c",
		cases = {
			"callout-page-lateral-sweep",
			"character-commands-ring-or-list",
			"type-roles-compile-to-native-fonts",
			"virtual-list-clamps-across-tabs",
		},
	},
	{
		id = "needs_live_input",
		cases = {
			"skinned-part-hover-state",
		},
	},
	{
		id = "paint_live",
		cases = {
			"alert-title-is-centred",
			"explicit-paint-beats-the-sheet",
			"path-strokes-in-theme-roles",
			"toggle-follows-a-live-palette",
		},
	},
	{
		id = "ports_content",
		cases = {
			"menu-edge-and-align-place-the-panel",
			"outline-section-closes-up",
			"pagination-arrows-hold-still",
			"pagination-targets-separate-and-centred",
			"recipe-dividers-start-at-the-text",
			"screen-header-and-scroll-share-height",
			"stage-draft-preview",
			"steps-number-marker-is-a-circle",
			"steps-underline-follows-and-springs",
		},
	},
	{
		id = "ports_foundation",
		cases = {
			"outline-indent",
			"selection-mark-hover",
			"selection-marks",
			"strong-divider-and-pane",
			"tab-rung",
			"underline-live",
			"utility-stroke",
			"xsmall-rung",
		},
	},
	{
		id = "ports_overlays",
		cases = {
			"callout-fixed-width-content-containment",
			"navbar-search-wraps-filter",
			"notice-affixed-banner-moves-content",
			"popover-capped-follows-a-shrinking-window",
			"popover-caps-and-side-hang",
			"popover-compact-sheet-then-anchored",
			"sheet-guarded-dismissal",
			"sheet-hug-follows-live-copy",
			"sheet-room-hug-hero-short",
			"sheet-scroll-policy-and-detectors",
			"snackbar-art-carve",
			"snackbar-paint-order",
		},
	},
	{
		id = "ports_pickers",
		cases = {
			"color-open-readiness",
			"color-phone-sheet-apply-on-screen",
			"color-plane-layers-and-ring",
			"color-touch-bubble-room",
			"dtp-grid-layout",
			"dtp-icon-toggle",
			"dtp-phone-fit",
			"dtp-ten-foot",
			"fields-accessories",
			"number-units",
			"picker-cards-live",
			"pickers-avatar-row-press",
			"slider-rotation-live",
		},
	},
	{
		id = "primitives",
		cases = {
			"scroll-view-canvas-and-stretch",
		},
	},
	{
		id = "reorder_displacement",
		cases = {
			"held-tile-opens-its-slot-and-settles-on-drop",
		},
	},
	{
		id = "scroll_live",
		cases = {
			"horizontal-scroll-view-steps-along-x",
			"scroll-view-canvas-covers-rows-and-gaps",
			"sheet-content-clears-theme-frame",
		},
	},
	{
		id = "sweep_b",
		cases = {
			"disabled-subtree",
		},
	},
	{
		id = "text_live",
		cases = {
			"button-labels-centred-in-every-package",
			"hidden-wallet-form-shrinks-before-reveal",
			"padded-text-draws-inside-its-inset",
			"styled-caption-does-not-hide-the-composition",
			"wrapped-region-readouts-use-the-offered-column-width",
			"wrapped-text-resizes-and-keeps-explicit-sizing",
		},
	},
	{
		id = "weak3_geometry",
		cases = {
			"uicorner-per-corner-probe",
		},
	},
	{
		id = "weak3_pointer",
		cases = {
			"color-plane-drag",
			"range-slider-drag",
			"skinned-part-press-state",
			"underline-hover",
		},
	},
	{
		id = "weak3_surfaces",
		cases = {
			"color-brick-field-above-grid",
			"color-swatch-square-cells",
			"dialog-actions-stack-and-row",
			"notice-preparation-preserves-visible-motion",
			"outline-disclosure-indent",
			"picker-dense-pointer-rows-live",
			"slider-custom-knob-footprint",
			"slider-rung-thin-rail-whole-target",
			"tabview-rung-centred",
		},
	},
	{
		id = "zoom_double_tap",
		cases = {
			"double-tap-over-cell-buttons-toggles-zoom",
		},
	},
}

local WEIGHTS: { [string]: number } = {
	["classb_collections/drag-across-rows-after-page-scroll"] = 90,
	["classb_collections/partial-lines-crop-and-offsets-clamp"] = 60,
	["classb_examples/settings-sync-compact-phone-every-text-size"] = 100,
	["classb_examples/word-keyboard-large-text-fits"] = 450,
	["classb_keyboard/circle-corner-wins-in-every-package"] = 60,
	["gallery/collection-toolbar-in-gallery"] = 50,
	["gallery/word-game-fits-the-phone"] = 90,
	["in24/sheet-reserves-card-feedback-clearance"] = 400,
	["navigation_split_view/geometry-feedback"] = 170,
	["needs_live_c/callout-page-lateral-sweep"] = 130,
	["ports_content/pagination-targets-separate-and-centred"] = 60,
	["ports_content/screen-header-and-scroll-share-height"] = 100,
	["ports_content/steps-underline-follows-and-springs"] = 60,
	["ports_overlays/notice-affixed-banner-moves-content"] = 80,
	["ports_pickers/color-open-readiness"] = 50,
	["ports_pickers/dtp-grid-layout"] = 40,
	["ports_pickers/dtp-phone-fit"] = 80,
	["ports_pickers/picker-cards-live"] = 60,
	["ports_pickers/pickers-avatar-row-press"] = 90,
	["reorder_displacement/held-tile-opens-its-slot-and-settles-on-drop"] = 70,
	["scroll_live/sheet-content-clears-theme-frame"] = 260,
	["weak3_pointer/color-plane-drag"] = 60,
}

local SHARDS = 24

local function assignments(): { [string]: number }
	local entries: { { name: string, weight: number } } = {}
	for _, suite in SUITES do
		for _, id in suite.cases do
			local name = `{suite.id}/{id}`
			table.insert(entries, { name = name, weight = WEIGHTS[name] or 20 })
		end
	end
	table.sort(entries, function(left, right)
		if left.weight ~= right.weight then
			return left.weight > right.weight
		end
		return left.name < right.name
	end)
	local loads: { number } = table.create(SHARDS, 0)
	local shardOf: { [string]: number } = {}
	for _, entry in entries do
		local lightest = 1
		for shard = 2, SHARDS do
			if loads[shard] < loads[lightest] then
				lightest = shard
			end
		end
		loads[lightest] += entry.weight
		shardOf[entry.name] = lightest
	end
	return shardOf
end

local function register(harness: Verify.Harness, shard: number)
	local shardOf = assignments()
	for _, suite in SUITES do
		for _, id in suite.cases do
			if shardOf[`{suite.id}/{id}`] == shard then
				harness:case(`original live {suite.id}/{id} on the Verify engine double`, function(check)
					Double.run(check, suite.id, id)
				end)
			end
		end
	end
end

return { register = register, shards = SHARDS }
