--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Double = require("./lib/live_double")

return function(harness: Verify.Harness)
	local suites: { { id: string, cases: { string } } } = {
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
			},
		},
		{ id = "motion_continuity", cases = {
			"clipping-checker-rejects-label-and-canvasgroup-overflow",
		} },
		{ id = "native_mechanisms", cases = {
			"grid-hugs-its-lines",
			"native-fixture-preserves-xml-codec",
		} },
		{ id = "navigation_split_view", cases = {
			"geometry-feedback",
		} },
		{ id = "ports_content", cases = {
			"stage-draft-preview",
		} },
		{ id = "ports_foundation", cases = {
			"strong-divider-and-pane",
		} },
		{ id = "text_live", cases = {
			"padded-text-draws-inside-its-inset",
		} },
	}
	for _, suite in suites do
		for _, id in suite.cases do
			harness:case(`original live {suite.id}/{id} on the Verify engine double`, function(check)
				Double.run(check, suite.id, id)
			end)
		end
	end
end
