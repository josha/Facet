# Adding a control

A control belongs in Facet when unrelated applications need the same interaction behavior. Domain copy, server rules and screen-specific decisions stay with the application. First try native Compose composition and the closest existing control.

## Contract and implementation

Define the value model, user callbacks, disabled behavior, cancellation, native root type and owned resources. Use writable Compose cells or explicit request callbacks; document whether a callback requests a value or follows an internal write. Return a native Instance and forward native properties/events/children through the common constructor path.

Implement the control beside its family in `src/ui`. The shared context supplies the caller's runtime, Host constructors, property forwarding, native observation, styles and input actions. It does not own another scene. Use Compose.cleanup for external subscriptions, native drag detectors for gestures, native layouts for geometry and the runtime's motion functions for animation.

Start with `lune run tools/lune/scaffold_cli control lower_snake_name`. It generates a strict native Frame control, registers its direct and named constructors before the registry freezes, adds its constructor to `Controls`, and exports its props from `Facet`. Extend the generated `Props` contract alongside the implementation; change its native root type if the control returns another class. Check the generated module and public facade with `python3 tools/check_types.py --files src/ui/lower_snake_name.luau src/ui/control_types.luau src/ui/init.luau src/init.luau`.

A control should consume only its own lower-case behavioral options. Leave native property names intact. Do not silently swallow unsupported options or add aliases for old application scaffolding.

## State and lifetime

Keep durable values in the caller's model. Create transient hover, open, drag or edit state under the mounted owner. A pooled/windowed row must not carry one item's state into another. Check cancellation when the owner disappears halfway through an interaction.

Read native bounds asynchronously for control-specific geometry. Do not introduce a general solver, focus graph, text measurement approximation, action transport or independent cleanup registry.

## Evidence

Use the native engine fixture to test real property bindings, event wiring, model writes, callbacks and teardown. Cover invalid inputs, cancellation, disabled state and reentrant updates. A test should observe behavior rather than duplicate the implementation.

Add a practical gallery scenario and exercise keyboard, gamepad, pointer/touch, long copy, theme switching and reduced motion in Studio as applicable. Update the API and capability catalog with the final contract. Run full verification and rebuild/check the local package before proposing the change.
