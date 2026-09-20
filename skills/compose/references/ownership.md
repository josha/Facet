# Ownership and structure

Use `show`, `switch`, `keyed` or `OrderedCollection` to change component structure.
Mount only finite roots. Components must not parent or destroy nodes or retain nested mount disposers.

Read the contract for your task:

- `docs/ownership.md`: ownership, disposal and failed-build cleanup.
- `docs/reactive.md`: dependency tracking and reactive lifetimes.
- `docs/api.md`: signatures and examples for structural directives.
