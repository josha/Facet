### Your own Compose

<!-- aliases: Your own Compose | your-own-compose -->

A game that already uses Compose must use one Compose instance for its state
and for Facet. Two instances make two reactive graphs. A value from one graph
does not reliably update a reader in the other graph.

`Facet.bind(Compose, Roblox)` returns a table with the same fields as `Facet`.
Its `Compose` and `Roblox` fields are the modules that you give. Its `controls`
and `themes` use only those modules. The default `Facet` table is
`bind` applied to the pinned copy.

```luau
local Compose = require(game.ReplicatedStorage.Packages.Compose.core)
local ComposeRoblox = require(game.ReplicatedStorage.Packages.Compose.roblox)
local Facet = require(game.ReplicatedStorage.Packages.Facet).bind(Compose, ComposeRoblox)
local runtime = ComposeRoblox.createRuntime()
local UI = Facet.controls(runtime)
```

Give both modules from the same Compose copy. Make the runtime with that
`Roblox` module.

`bind` rules:

- The Facet tests use the Compose commit in `COMPOSE_COMMIT`. Facet supports a
  later Compose commit when it keeps the functions that Facet uses and their
  behavior.
- `bind` stops with an error when the Compose module does not have a function
  that Facet uses. The error names the function and the tested commit. `bind`
  cannot find a change in behavior. Run your tests when you change Compose.
- A control stops with an error that names the control when no owner of its
  Compose instance is active. This occurs when you build a control outside
  `runtime.mount`, or when the runtime comes from a different Compose instance.
- A control stops with an error that names the control and the option when an
  option is a cell or formula from a different Compose instance. `read` of a
  value from a different Compose instance also stops with an error.
