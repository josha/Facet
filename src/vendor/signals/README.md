# Roblox Signals

Vendored from [Roblox/signals](https://github.com/Roblox/signals) commit
`7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60` (Signals 0.9.0), MIT licensed.
Included in offline source and Roblox package builds. No network at runtime.

Only imports and file extensions are adapted for Facet's shared Luau/Rojo/Lune
require paths. The reactive algorithm and scheduler are upstream code.
Facet lifecycle, diagnostics and ordered terminal work live in `core/signals.luau`.

| Local file | Upstream file | Git blob SHA |
|---|---|---|
| LICENSE | LICENSE | d94dfa11b578f738374334ea71a9190e9301c350 |
| signals.luau | modules/signals/src/Signals.lua | 33e3f4d7c006ed71d11ed5ed8beb639213a1092c |
| callUserSpace.luau | modules/signals/src/callUserSpace.lua | 717dbea58191310aff28c69b359598ce9dd39176 |
| scheduler.luau | modules/signals-scheduler/src/SignalsScheduler.lua | c9be6cf755f08c85dcfa7560999b61fc07fb3602 |
| flags.luau | modules/signals-flags/src/init.lua | 00d3cc06d33aa782ad861518c1cd04f5aff092b5 |

`license.luau` carries the same MIT notice inside Roblox model builds.
`UPSTREAM.lock` pins the adapted source bytes; the dependency gate rejects
unlisted files or changed source without a deliberate pin update.
