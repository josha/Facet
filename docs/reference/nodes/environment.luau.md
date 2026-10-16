# environment.luau

```luau
local function Apps(tabs, selection)
	local env = UI.environment()
	return UI.TabView "Apps" {
		tabs = tabs,
		selection = selection,
		railWidth = function(use)
			return if Facet.adaptive.sizeClassAtLeast(use(env.sizeClass), "wide") then 176 else 148
		end,
	}
end
```

For a choice that depends on the space of one container, observe the
`AbsoluteSize` of that container. The environment describes the viewport.
