# Maintaining Facet

The public root exports Compose, its Roblox host, the control factory, themes and
control types. `src/ui` implements controls directly over the supplied runtime.
`src/vendor/compose` is generated and read-only. There is no client adapter layer
or Facet scene, renderer, application, general layout solver or focus graph.

Control implementations consume their behavioral options and forward native
properties, event keys, attributes and children unchanged. Common private helpers
only construct native components or observe native properties. They do not own a
runtime, frame loop or application lifetime.

Theme definitions compile to native StyleSheets. Callers own StyleLinks. Do not
write explicit default paint properties that mask stylesheet rules.

Control policy tests use a native engine double. Geometry, hit testing, IME,
scrolling and input eligibility require live Studio evidence. Keep per-family
behavior coverage when retiring tests of removed mechanisms. The verification
report must identify any remaining coverage gap.

Use the [contributor workflow](../CONTRIBUTING.md), [API](reference/api.md) and
[control playbook](extending/new-control.md).
