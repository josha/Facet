--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Double = require("./live_double")

local SUITES: { { id: string, cases: { string } } } = {
	{
		id = "classb_collections",
		cases = {
			"drag-across-rows-after-page-scroll",
			"page-scroll-moves-the-table-body",
			"plate-decoration-stays-inside-the-band",
		},
	},
	{
		id = "classb_examples",
		cases = {
			"outpost-terminal-holds-canvas-every-text-size",
			"settings-sync-compact-phone-every-text-size",
		},
	},
	{
		id = "classb_keyboard",
		cases = {
			"clear-button-trailing-and-centred",
			"slider-rest-idle-resize-clearance",
		},
	},
	{
		id = "classb_navigation",
		cases = {
			"navigation-gameplay-lifetime",
			"pageview-fixed-in-scroller",
			"path-clipped-in-scroll",
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
			"word-game-fits-the-phone",
		},
	},
	{
		id = "in24",
		cases = {
			"component-setup-error-and-throwing-cleanup",
			"compose-delivery-order",
			"image-scale-mode-renders",
			"presence-retires-until-exit",
			"ring-geometry-only-on-real-change",
			"stack-pop-retires-until-motion-ends",
			"touch-hint-with-no-touch-binding",
			"touch-page-view-dots",
		},
	},
	{
		id = "in47",
		cases = {
			"actions-released-with-their-owner",
			"hover-follows-the-pointer",
			"one-action-many-devices",
			"touch-one-action-many-devices",
		},
	},
	{
		id = "layout_geometry",
		cases = {
			"callout-edge-gap-shift-clamp",
			"callout-tail-centre-border-corners",
			"circle-button-authored-axes",
			"navigation-stack-root-box-and-back-chrome",
			"panel-insets-reserve-native-padding",
			"progress-short-end-label-keeps-its-text",
			"tab-head-accessory-above-rail",
			"vertical-segments-stack-share-width-floor",
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
			"disclosure-description-header",
			"progress-skin-under-scale",
		},
	},
	{
		id = "paint_live",
		cases = {
			"explicit-paint-beats-the-sheet",
			"path-strokes-in-theme-roles",
		},
	},
	{
		id = "ports_content",
		cases = {
			"outline-section-closes-up",
			"pagination-arrows-hold-still",
			"pagination-targets-separate-and-centred",
			"recipe-dividers-start-at-the-text",
			"stage-draft-preview",
			"steps-number-marker-is-a-circle",
			"steps-underline-follows-and-springs",
		},
	},
	{
		id = "ports_foundation",
		cases = {
			"selection-marks",
			"strong-divider-and-pane",
			"tab-rung",
			"utility-stroke",
			"xsmall-rung",
		},
	},
	{
		id = "ports_overlays",
		cases = {
			"callout-fixed-width-content-containment",
			"navbar-search-wraps-filter",
			"popover-capped-follows-a-shrinking-window",
			"sheet-guarded-dismissal",
		},
	},
	{
		id = "ports_pickers",
		cases = {
			"dtp-grid-layout",
			"fields-accessories",
			"slider-rotation-live",
		},
	},
	{
		id = "scroll_live",
		cases = {
			"scroll-view-canvas-covers-rows-and-gaps",
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
			"range-slider-drag",
			"skinned-part-press-state",
		},
	},
	{
		id = "weak3_surfaces",
		cases = {
			"dialog-actions-stack-and-row",
			"notice-preparation-preserves-visible-motion",
			"outline-disclosure-indent",
			"slider-rung-thin-rail-whole-target",
			"tabview-rung-centred",
		},
	},
}

local SHARDS = 4

local function register(harness: Verify.Harness, shard: number)
	local index = 0
	for _, suite in SUITES do
		for _, id in suite.cases do
			index += 1
			if index % SHARDS == shard % SHARDS then
				harness:case(`original live {suite.id}/{id} on the Verify engine double`, function(check)
					Double.run(check, suite.id, id)
				end)
			end
		end
	end
end

return { register = register, shards = SHARDS }
