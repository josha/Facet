--!strict

return {
	package = {
		name = "josha/facet",
		version = "0.12.0",
		files = {
			"/src/**",
			"/tools/**",
			"/docs/**",
			"/skills/**",
			"/.luaurc",
			"/README.md",
			"/CHANGELOG.md",
			"/LICENSE",
			"/THIRD_PARTY_NOTICES.md",
		},
		metadata = {
			description = "Roblox UI controls built on Compose and native engine APIs.",
			license = "MIT",
			repository = "https://github.com/josha/Facet",
			exports = {
				Facet = "src",
			},
		},
		dependencies = {},
		dev_dependencies = {
			compose = {
				sourceKind = "github",
				source = "https://github.com/voidmeld/compose",
				rev = "fe528148431142c2367af3158984106b67998e99",
			},
			verify = {
				sourceKind = "github",
				source = "https://github.com/voidmeld/verify",
				rev = "35c5590efa9fdb9fc12319a7bc9455a81c2d1970",
			},
		},
	},
}
