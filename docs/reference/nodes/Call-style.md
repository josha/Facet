### Call style

<!-- aliases: Call style | call-style -->

Call-style contract and option values.

Use a dot for fields that are plain functions: `Facet.app`, `app.mount`,
`app.dispose`, `runtime.mount`, `runtime.mountFragment`, `runtime.decorate`
`runtime.spring` and `runtime.tween`. Use a colon for the Compose runtime
methods: `runtime:dispose()`, `runtime:batch(body)`, `runtime:watch(body)`,
`runtime:settle()` and `runtime:pending()`. Compose declares these with `self`,
and the type check rejects the dot form. Cells use a colon:
`cell:set(value)`, `cell:update(fn)` and `cell:peek()`.
