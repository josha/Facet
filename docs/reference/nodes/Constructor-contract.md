## Constructor contract

<!-- aliases: Constructor contract | constructor-contract -->

`UI.Button(spec)` and `UI.Button("Name")(spec)` are equivalent construction
forms. The second form sets the name. Every constructor returns a native
Instance. `ref = function(instance) ... end` receives that root. Make controls
inside a Compose owner. This is usually the component that you give to
`runtime.mount`.

Property tables accept native Instances and Compose directives as children.
A `nil` child omits that entry.

Open:

- [Factory-options](Factory-options.md)
- [Haptics](Haptics.md)
- [Instances-you-hand-to-a-presenter](Instances-you-hand-to-a-presenter.md)
- [Modal-input](Modal-input.md)
- [Motion](Motion.md)
- [Options-and-native-properties](Options-and-native-properties.md)
- [Selection](Selection.md)
- [State](State.md)
