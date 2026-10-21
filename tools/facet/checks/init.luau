--!strict

local Rule = require("./lib/rule")

local rules: { Rule.Rule } = {
	require("@self/plan"),
	require("@self/docs_nodes"),
	require("@self/docs_samples"),
	require("@self/facetbench"),
	require("@self/architecture"),
	require("@self/type_policy"),
	require("@self/vendor"),
	require("@self/comments"),
	require("@self/screen_key_bindings"),
	require("@self/source_size"),
	require("@self/theme_drift"),
	require("@self/theme_artifacts"),
	require("@self/doc_style"),
	require("@self/links"),
	require("@self/maintainer_map"),
	require("@self/example_drift"),
	require("@self/call_shape_drift"),
	require("@self/public_allowlist"),
	require("@self/scenario_requires"),
	require("@self/library_purity"),
	require("@self/word_data"),
	require("@self/text_encoding"),
}

return table.freeze(rules)
