--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Double = require("./lib/live_double")

return function(harness: Verify.Harness)
	local suites: { { id: string, cases: { string } } } = {
		{
			id = "classb_collections",
			cases = {
				"page-scroll-moves-the-table-body",
			},
		},
		{
			id = "classb_examples",
			cases = {
				"outpost-terminal-holds-canvas-every-text-size",
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
				"underline-follows-rehomed-strip",
				"tab-reorder-keeps-page-geometry",
				"path-clipped-in-scroll",
			},
		},
		{
			id = "classb_themes",
			cases = {
				"authored-metric-native-stroke",
				"status-round-containment",
				"skeleton-circle-round-sweep",
				"skeleton-band-contained",
				"skeleton-parent-alignment",
			},
		},
		{
			id = "focus_probe",
			cases = {
				"F9-arrow-keys-drive-engine",
				"F11-selection-image-part",
			},
		},
		{
			id = "frame_stability",
			cases = {
				"native-indeterminate-progress-layout",
				"negative-indeterminate-progress-layout-resize",
				"negative-one-frame-late-resize",
				"negative-late-resize-after-explicit-state-change",
				"native-text-change-starts-a-new-state",
				"negative-late-resize-after-text-change",
				"native-scroll-change-starts-a-new-state",
				"negative-late-resize-after-scroll-change",
				"native-visibility-change-starts-a-new-state",
				"negative-late-resize-after-visibility-change",
				"negative-native-sample-errors-fail-the-observation",
				"negative-gradient-mask-does-not-hide-a-late-visible-resize",
			},
		},
		{
			id = "in24",
			cases = {
				"component-setup-error-and-throwing-cleanup",
				"compose-delivery-order",
				"image-scale-mode-renders",
				"ring-geometry-only-on-real-change",
				"touch-page-view-dots",
				"presence-retires-until-exit",
				"touch-hint-with-no-touch-binding",
			},
		},
		{
			id = "in47",
			cases = {
				"actions-released-with-their-owner",
				"one-action-many-devices",
				"touch-one-action-many-devices",
			},
		},
		{
			id = "layout_geometry",
			cases = {
				"circle-button-authored-axes",
				"callout-edge-gap-shift-clamp",
				"callout-tail-centre-border-corners",
				"vertical-segments-stack-share-width-floor",
				"tab-head-accessory-above-rail",
			},
		},
		{
			id = "mobile_regressions",
			cases = {
				"segmented-opening-layout",
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
			},
		},
		{
			id = "needs_live_b",
			cases = {
				"disclosure-description-header",
			},
		},
		{
			id = "ports_content",
			cases = {
				"stage-draft-preview",
				"pagination-targets-separate-and-centred",
				"pagination-arrows-hold-still",
				"steps-underline-follows-and-springs",
				"steps-number-marker-is-a-circle",
				"recipe-dividers-start-at-the-text",
			},
		},
		{
			id = "ports_foundation",
			cases = {
				"strong-divider-and-pane",
				"utility-stroke",
				"tab-rung",
				"xsmall-rung",
			},
		},
		{
			id = "ports_overlays",
			cases = {
				"callout-fixed-width-content-containment",
				"navbar-search-wraps-filter",
			},
		},
		{
			id = "ports_pickers",
			cases = {
				"fields-accessories",
				"dtp-grid-layout",
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
				"padded-text-draws-inside-its-inset",
				"wrapped-region-readouts-use-the-offered-column-width",
				"styled-caption-does-not-hide-the-composition",
			},
		},
		{
			id = "weak3_geometry",
			cases = {
				"uicorner-per-corner-probe",
			},
		},
		{
			id = "weak3_surfaces",
			cases = {
				"slider-rung-thin-rail-whole-target",
				"outline-disclosure-indent",
				"tabview-rung-centred",
			},
		},
	}
	for _, suite in suites do
		for _, id in suite.cases do
			harness:case(`original live {suite.id}/{id} on the Verify engine double`, function(check)
				Double.run(check, suite.id, id)
			end)
		end
	end
end
