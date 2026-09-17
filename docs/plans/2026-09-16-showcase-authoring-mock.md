# Showcase authoring rehearsal

This rehearsal precedes runtime changes. The source is the Motion section of
`examples/gallery/client/settings_panel.luau`. Names below are proposed API until
the implementation and its tests land. All expressions use native Roblox Luau.

## Before: a preference, a mirrored signal, a watcher, and control handles

```luau
local scope = core:scope("gallery-settings-panel")
local reducedFact = env:get("reducedMotion")
local initial = settings_panel.modeOf(reducedFact:get())
local setting = scope:own(core:signal(initial))
local mode = scope:own(core:signal(initial))
scope:own(core:observe(reducedFact, function(value)
	mode:set(settings_panel.modeOf(value))
end))
local motionPicker = Facet.Controls.Picker(core, {
	id = "MotionMode",
	label = COPY.motion,
	style = "segmented",
	options = {
		{ value = "full", label = COPY.full },
		{ value = "reduced", label = COPY.reduced },
	},
	selected = mode,
	onChange = function(value)
		setting:set(value)
		applyMode(value)
	end,
})
scope:own(motionPicker)
local section = UI.VStack {
	id = "Motion", width = UI.fill(), gap = "xs",
	children = {
		motionPicker.blueprint,
		UI.Text {
			id = "Note", text = COPY.motionNote, textSize = "caption",
			role = "secondary", width = UI.fill(),
		},
	},
}
```

All new examples use `local UI = Facet.View`.

## After: state, a recipe, and an ordered description

```luau
local MotionSettings = Facet.component(function(ui, props)
	local reduced = ui.read(props.env:get("reducedMotion"))
	local function mode()
		return if reduced() then "reduced" else "full"
	end
	local preference, setPreference = ui.state(mode())
	ui.watch(preference, function(value)
		props.env:set("reducedMotion", value == "reduced")
	end)
	return UI.VStack {
		id = "Motion", width = UI.fill(), gap = "xs",
		UI.Picker {
			id = "MotionMode", label = COPY.motion, style = "segmented",
			options = {
				{ value = "full", label = COPY.full },
				{ value = "reduced", label = COPY.reduced },
			},
			selected = mode, onChange = setPreference,
		},
		UI.Text {
			id = "Note", text = COPY.motionNote, textSize = "caption",
			role = "secondary", width = UI.fill(),
		},
	}
end)
```

The host still owns its preference across demo changes. In the actual migration,
keep that preference in the existing host model and pass its getter/setter to the
component; do not reset it whenever the settings section mounts. The example
above demonstrates local state, but the rehearsal reveals that local state is
the wrong lifetime for a persistent showcase preference.

There is another subtlety: picking the stored preference while a demo overrides
the environment must still apply it. A change-only watcher cannot observe an
equal setter write. The final handler therefore explicitly performs this command:

```luau
onChange = function(value)
	props.setPreference(value)
	props.env:set("reducedMotion", value == "reduced")
end,
```

This is shorter and more faithful than a watcher for an event. Use property
recipes for values, event handlers for commands, and watchers for actual changes.

## A denser showcase card

```luau
local CounterCard = Facet.component(function(ui)
	local count, setCount = ui.state(0)
	return UI.VStack {
		gap = "m",
		UI.Text "Live counter",
		UI.Text(function() return `Count: {count()}` end),
		UI.HStack {
			gap = "s",
			UI.Button {
				label = "Add one",
				onActivate = function() setCount(count() + 1) end,
			},
			UI.Button {
				label = "Reset", enabled = function() return count() > 0 end,
				confirm = { title = "Reset counter?", message = "The count returns to zero." },
				onActivate = function() setCount(0) end,
			},
		},
	}
end)
```

## Decisions from the rehearsal

- Children use consecutive numeric slots, visited explicitly from 1 to the
  validated length. Reject holes, invalid indices and simultaneous numeric
  children plus `children`; never derive layout order from named keys.
- `UI.Text "literal"` and `UI.Text(getter)` are ordinary Luau function calls.
  `() => expression` is not valid Luau. No compiler or alternate language.
- A property function computes a value; a declared callback such as `onActivate`
  handles an event. Validate using the property schema, never guess by arity.
- Components run once per mount. The mounted component owns its
  state and subscriptions; row components get row lifetimes. Property bindings
  belong to their mounted branch or row. Descriptions allocate no subscriptions.
- Remove the mirrored `mode` signal: the environment is already the truth.
  Memoize only shared or expensive calculations; short recipes need no name.
- Retain explicit ownership at integration boundaries (`ui.own`), and keep
  low-level `Core`, scopes and control handles available for advanced callers.
- Confirmation uses the existing Alert and presenter focus/cancellation path.
  Its action runs only on acceptance and gets the original activation metadata.
- Stable collection keys preserve row identity, while row getters expose the
  latest item for that key. Keep existing virtualization for large lists.

## Validation status

Before runtime implementation: native shorthand and indexed-child type probes
passed luau-lsp; malformed children failed the type probe. Live Studio validation
is pending a connected Studio instance (the discovery tool returned no instances).

## Implementation follow-through

The final motion section keeps the preference in the host, derives live mode
from the environment, and applies changes in the picker callback. Settings Sync
now uses a component with reactive property functions and ordered array children.
Live Studio accepted the native syntax and exercised pending, accepted and rejected
server replies through mouse input on the migrated screen.
