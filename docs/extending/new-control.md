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

## Layout rules

- Facet's model and the native layout must agree. When Facet decides
  something about layout, such as that an empty region takes no room or
  where a row wraps, make the native tree do the same: hide what the model
  leaves out, and size what the model sizes.
- Native automatic size does not follow every change. A container that hugs
  children that it also stretches does not measure them again when they grow
  or shrink. A Frame with `AutomaticSize` and no layout object can stay one
  step behind an automatic-size child. Give a wrapper a list layout, and call
  `kit.regrow` for a list that both hugs and stretches.
- Test that content can grow and shrink after it mounts, not only that the
  first layout is correct.
- Make the common game layout the default: a value sits beside its bar, and
  the panels of one HUD row have one height. A game must not need to measure
  or set pixel sizes for a common layout to look right.

## Scaffolding

1. Run `lute run tools/facet scaffold control lower_snake_name`. The
   scaffold does these steps:
   - It makes a strict native Frame control.
   - It registers the direct and named constructors before the registry
     freezes.
   - It adds the constructor to `Controls`.
   - It exports the props of the control from `Facet`.
2. Extend the generated `Props` contract together with the implementation. If
   the control returns a different class, change its native root type. When
   the control has options, declare them as one table type, such as
   `GaugeOptions`, in the types module of its family. Add a recipe for
   `GaugeProps` to `tools/facet/lib/control_props.luau`. Then run
   `lute run tools/facet types props`. The tool writes one flat props
   type with the native root properties, the options and the children. A flat
   type lets strict mode check literal options without casts. The
   `control-props` producer fails when the generated module is out of date.
3. Check the generated module and the public facade:
   `lute run tools/facet types --files src/ui/lower_snake_name.luau src/ui/control_types.luau src/ui/init.luau src/init.luau`.

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
