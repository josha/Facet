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
				rev = "206648c0becb496919ca7af3855fc775bb96d900",
			},
			verify = {
				sourceKind = "github",
				source = "https://github.com/voidmeld/verify",
				rev = "2e8cedeb260dd61d29b6f4be51a5fc250254e80b",
			},
		},
	},
}
