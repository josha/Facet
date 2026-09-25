# Adding a control

A control belongs in Facet when unrelated applications need the same
interaction behavior. Domain copy, server rules and screen-specific decisions
stay with the application. First, try native Compose composition and the
closest existing control.

## Contract and implementation

Define these items:

- the value model,
- the user callbacks,
- the disabled behavior,
- cancellation,
- the native root type,
- the owned resources.

Use writable Compose cells or explicit request callbacks. Document whether a
callback requests a value or follows an internal write. Return a native
Instance. Forward native properties, events and children through the common
constructor path.

Put the control next to its family in `src/ui`. The shared context supplies the
runtime of the caller, the Host constructors, property forwarding, native
observation, styles and input actions. It does not own another scene.

- Use `Compose.cleanup` for external subscriptions.
- Use native drag detectors for gestures.
- Use native layouts for geometry.
- Use the motion functions of the runtime for animation.

## Scaffolding

1. Run `lune run tools/lune/scaffold_cli control lower_snake_name`. The
   scaffold does these steps:
   - It makes a strict native Frame control.
   - It registers the direct and named constructors before the registry
     freezes.
   - It adds the constructor to `Controls`.
   - It exports the props of the control from `Facet`.
2. Extend the generated `Props` contract together with the implementation. If
   the control returns a different class, change its native root type.
3. Check the generated module and the public facade:
   `python3 tools/check_types.py --files src/ui/lower_snake_name.luau src/ui/control_types.luau src/ui/init.luau src/init.luau`.

A control consumes only its own lower-case behavioral options. Keep native
property names. Do not silently accept unsupported options. Do not add aliases
for the old application scaffolding.

## State and lifetime

Keep durable values in the model of the caller. Make transient hover, open,
drag or edit state under the mounted owner. A pooled or windowed row must not
carry the state of one item into another item. Check cancellation when the
owner is removed during an interaction.

For control-specific geometry, read native bounds asynchronously. Do not add a
general solver, focus graph, text measurement approximation, action transport or
independent cleanup registry.

## Evidence

1. Use the native engine fixture to test real property bindings, event wiring,
   model writes, callbacks and teardown. Cover invalid inputs, cancellation,
   disabled state and reentrant updates. A test must observe behavior. It must
   not duplicate the implementation.
2. Add a practical gallery scenario. In Studio, exercise keyboard, gamepad,
   pointer and touch input, long copy, theme switching and reduced motion, as
   applicable.
3. Update the API reference and the capability catalog with the final contract.
4. Run full verification. Rebuild and check the local package before you
   propose the change.
