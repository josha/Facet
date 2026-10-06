---
name: compose
description: Invoke only while consuming Compose's public scene-composition and ownership API in a Luau application. Do not invoke it to change Compose itself, or for application logic, networking, physics, persistence, or asset loading.
---

# Compose consumer

This skill helps a Luau application consume the public scene-composition and ownership API of Compose.

1. Find the pinned public package. Reuse the runtime and the nearest component of the application.
   - For a first component, follow [the bootstrap route](references/api.md) to create a runtime.
   - If the pin is missing, resolve it through the dependency procedure of the application. Do not substitute internal imports.
2. Bind `local Host = runtime.constructors`. Build nodes with `Host.Kind { ... }`.
   - The table caches constructors for that runtime. For a dynamic kind, use `runtime.create(kind)`.
   - Keep instance state inside the component. Return composition. Use stable keys for structural changes.
3. Use `borrow` for nodes that Compose must not destroy. Use `adopt` for a whole node that Compose must destroy.
   - Bind external handles to an owner.
   - If ownership is undecided, stop and report that ownership or lifetime is undecided.
4. Reproduce the changed behavior with the host, the ownership root and the inputs of the consumer.
   - For a layout repair, inspect the final geometry and the hit targets, including safe areas and resizing.
   - A copied layout formula does not test the composed result.
5. If the pinned tools exist, run `lute run tools/compose-check.luau --root <source>`.
   - Check the changed behavior and ownership with focused consumer tests.
   - Run the full gate of the application once on the final bytes.
   - Record the dependency pin, the candidate, the check result and the evidence path.

The skill is finished when every created node has a decided owner and the gate of the application passes at integration.
It is also finished when you report an unresolved dependency or ownership boundary.

Read one reference for the contract that you need:

- [Public API and first component](references/api.md)
- [Ownership and reactive structure](references/ownership.md)
- [Roblox, profiling, or authoring](references/consumer-guides.md)
