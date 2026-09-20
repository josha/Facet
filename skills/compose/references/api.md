# API

Read `docs/quickstart.md` before writing your first component.
Use `docs/api.md` to choose a public API. Pass a readable directly when no
transformation is needed. Use a reactive body only for a computation. For internal changes, stop
and follow the root `AGENTS.md`.

Use `local Host = runtime.constructors` for host constructors such as `Host.Text { ... }` where
the host supports that kind. The table caches each constructor on its first lookup. Each constructor belongs to that runtime.
Use `runtime.create(kind)` when the kind is dynamic. Core supplies reactive helpers, not host
constructors. An application may export its constructor table as its own `Compose` module and
require core separately as `ComposeCore`.
