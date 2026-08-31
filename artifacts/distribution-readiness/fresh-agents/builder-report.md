# Fresh-agent screen build (DR-29) — 2026-08-31: SUCCESS

A fresh agent with only the public clone built an adaptive, themed, stateful
settings panel (toggles, slider, transactioned defaults, adaptive action row,
idle/close teardown) from the documentation alone: README → guide index →
concepts → getting-started → consumer example → api.md. Proof: a 15-case spec
through the fake adapter — mount, theme paint+metrics (fallback arm named
honestly), input-driven toggle and drag, reactive readout, transaction, two
viewports re-solving the same nodes, preferred text, and registry-clean
teardown — all green, with eight mutations each reddening the intended cases.

Findings handed to the docs owner (fix round in flight): the real test idiom
(tests/lib/fake_target) is taught nowhere; fake_target is absent from the
Package/.rbxm install routes; a consumer spec has no documented home
(run_one resolves tests/ only, and an unregistered spec trips the registration
guard); slider sub-node paths and the drive verbs are undocumented; the
fill-width remedy for sliders is stated as a hazard without its fix; theme
install ordering vs present is unstated; api.md contradicts itself on the
adaptive.conditions memo count (six vs eighteen; four example comments carry
the stale six); three doc snippets reference an undefined `rootHandle`; the
install-failure sentence reads as a contradiction at point of use; the README
recommends the not-yet-existing Package route above the working Rojo route.
