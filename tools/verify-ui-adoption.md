# Verify UI fixtures

Verify supplies shared engine test mechanisms: clone allocation and reference
remapping, tags, class and ancestor lookup, focus state, style maps, path
storage, reflection registration, and datatype validation. Facet keeps
control-specific cases and fixture configuration in `tests/lib/native_engine.luau`.
The dependency pin and hashes are in `tools/vendor/verify/UPSTREAM.lock`.

## Adapter boundary

The fixture supplies native defaults, method doubles, datatype constructors,
and geometry, text, and input injection. Animated page changes use explicit
instant doubles. These mechanisms do not prove rendering or animation.

Roblox UIScale, AbsoluteSize, and AnchorPoint provide native scale and
centering. Collection geometry uses native observations. Compose owns reactive
bindings and cleanup. Motion values belong to theme tokens.

Run `lute run tools/facet gate full` for the committed plan and integration
checks. Use live Studio reports for geometry and input. See
[verification scope](../docs/guide/18-verification-scope.md) for evidence limits.
