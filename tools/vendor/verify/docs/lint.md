# Lint policy

The complete gate runs `lute lint -c lint.config.luau` on each maintained Luau tree. It also runs
`luau-lsp analyze` in strict mode for every maintained source, test, tool, example and lint
configuration. Exported records and callbacks carry concrete types. Dynamic host members, arbitrary
assertion values and heterogeneous callback arguments remain explicit boundaries; a strict directive
alone does not prove those values safe. The analyzer checks consumers against the installed SDK types;
it excludes diagnostics inside external SDK and generated build directories.

`tools/check-no-any.luau` parses every maintained Luau file, including tests, tools and examples.
Each file must start with `--!strict`. Explicit `any` types and `--!nonstrict` or `--!nocheck`
directives fail the gate. Use concrete types, correlated generics and validated `unknown` at
external boundaries. Do not hide weak typing behind aliases or unchecked boundary casts.

The explicit configuration keeps Lute's defect rules on. It turns off only
`global_function_in_scope` and `unused_variable`. At the pinned runtime, those two rules misreport
forward-declared recursion and locals used as assignment-target bases. `luau-lsp` retains the real
unused-local signal.

`verify-check` is the consumer-semantic layer:

```console
lute run tools/verify-check.luau path/to/specifications
```

It recognizes `*.verify.luau` as portable specifications, with `*.lute.verify.luau` and
`*.roblox.verify.luau` as explicit host variants. It rejects ambient scheduling, clocks, and host
access in portable specifications. It rejects external mutation authority in every specification.
It rejects unmeasured `--!native` annotations. These are architectural checks a general-purpose
linter cannot infer.

The tool calls `Consumer.scanTree(root, { listDir, readFile })`
([public consumer root](../src/consumer/init.luau)). `scanTree` owns traversal, specification detection, and exemption tracking.
Consumer lint runners can reuse this work when integrating `Consumer.scan`/`scanProductionPaths`.
`scanTree` also runs `scanProductionPaths` over every discovered path, including files that are not specifications.
The same call detects `.verify.luau` files or Verify imports in a production source graph.
