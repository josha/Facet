# Run cases

Use one command for simulator, Studio, published Player and Open Cloud tests. Each entry returns ordinary
named cases and harness options. Each host produces the standard report. There is no separate
end-to-end case language.

Run from a workspace containing both the framework and test modules. Paths are relative to that
working directory. Lute cannot resolve a test module outside its loading root; use their common parent
as the working directory rather than an external `/tmp` entry.

From this repository:

```sh
lute run tools/run.luau --entry examples/platform-entry.luau
lute run tools/run.luau --entry examples/platform-entry.luau --host studio --capture
lute run tools/run.luau --entry examples/platform-entry.luau --case instance-state
```

The first two commands run the same assertions against simulated and native instances.
[The entry](../examples/platform-entry.luau) chooses the host binding. It exports a function receiving
`simulator`, `studio` or `player` and returning `{ cases, options, now }`. `cases` contains
`Core.NamedCase` values with explicit unique IDs. `options` is `Core.RunOptions`; `now` is the clock.
Bind per-case resources through `options.bind`. The harness owns their cleanup.

`Core.runCases(cases, options, now, ids?)` validates the collection and exact selection before execution.
Reports record whether selection was explicit and the available case count. Unknown, duplicate or empty selections fail. An omitted selection runs every case. Do not also set
`options.selection`. Each case declares a finite timeout and the capabilities its observations need.

## Commands and evidence

| Option | Meaning |
| --- | --- |
| `--entry module.luau` | Portable factory module; required. |
| `--host simulator\|studio\|player\|open-cloud` | Defaults to simulator. |
| `--case id` | Exact case ID; repeat to select several. |
| `--deadline seconds` | Host execution budget; defaults to 90. Preparation is outside this budget. |
| `--output directory` | Parent for unique evidence directories; defaults to `.verify`. |
| `--framework directory` | Framework checkout; inferred from this command's path. |
| `--root directory` | Additional mounted module directory; repeat as needed. Literal imports are followed automatically. |
| `--place fixture.rbxlx` | Existing Studio fixture containing the mounted entry; otherwise build an isolated floor/spawn fixture. |
| `--context Server\|Client` | Studio execution side; defaults to Server. |
| `--players count` | Studio server with 1–8 clients. |
| `--client file`, `--server file` | Portable bootstrap modules returning functions; mounted and called automatically. |
| `--capture` | Durable final Studio view; single-client runs only. |
| `--require-media type` | Require a saved artifact with this exact MIME type for each returned case. |
| `--place-id number` | Published Player or Open Cloud place. |
| `--cloud module.luau` | Open Cloud: caller module returning `{ request, authorize }`. |
| `--universe-id id`, `--place-version n` | Open Cloud universe and exact place version. |

Exit zero means a nonempty report with every selected case passed. Skips, unsupported requirements,
timeouts, partial reports and failed cleanup exit nonzero. A selected pass is not whole-project acceptance.

Each run keeps `report.json`, `summary.txt` and available artifacts together. Simulator output is in
`host.log`; Studio process/MCP diagnostics stay below `studio/`. Failed native launches retain diagnostics.
Captures keep case, actor and checkpoint identity. Temporary Roblox URIs, remote links, missing files
and empty files are listed as missing durable evidence. They do not satisfy media requirements.
A final Studio image proves the final view only, not an earlier checkpoint or visual quality.

For programmatic use, `Lute.platform.run(options)` returns `{ report, directory, reportPath }`.
It accepts the corresponding typed options plus `requiredEvidence`, a list of
`{ caseId, actor?, checkpoint?, mediaType }`. Require each actor separately when a multiplayer claim
needs both views. Missing required evidence adds a failed case to the same report.
`Lute.evidence.write` and `finish` persist reports from custom hosts using the same rules.

## Gates and benchmarks

```sh
lute run examples/gate.luau [producer-id ...]
lute run examples/benchmark.luau
lute run tools/gate.luau [--native] [--only producer]...
```

The last command also drives the Lune checks, which need `lune` on `PATH`.

[The gate example](../examples/gate.luau) runs build, test-module, benchmark and deferred native producers as one plan and prints the
verdict; naming ids narrows it, which prints `selected`. `tools/gate.luau` is this repository's own declarative gate:
`--only` narrows, and the native producers are deferred unless `--native` is given. See
[declarative gates](execution.md#declarative-gates) and [benchmarks](experience.md#benchmarks).

## Multiplayer

```sh
lute run examples/multiplayer.luau simulator
lute run examples/multiplayer.luau studio
```

These run [one case](../examples/multiplayer/case.luau): click in the first client, observe the server,
then observe the second client. The simulator supplies explicit application fakes. Studio uses two
actual clients, virtual input and replication. Both use the same context operations and verdicts.
Simulation supplies no native input, rendering, physics or replication proof. Native per-client
CaptureService references remain temporary; this example does not claim retained screenshots or
visual judgment. Supply a durable capture adapter and actor-specific requirements when those matter.

## Published Player

Build an isolated test fixture once with `Lute.platform.buildPublished`:

```luau
Lute.platform.buildPublished {
    output = testPlacePath,
    entry = "examples/platform-entry.luau",
    authorizedUserIds = testAccountIds,
    context = "Server",
}
```

Publish that file to your test experience using your authorized publishing workflow. Then run:

```sh
lute run tools/run.luau --entry examples/platform-entry.luau --host player --place-id YOUR_TEST_PLACE_ID
```

The generated bootstrap authorizes the actual player on the server, validates the requested entry and
selection from join data, and permits one run per player connection. `context = "Client"` runs the entry
on that authorized client; the default runs it on the server. Both print the standard framed report in
the owning client. Keep test account IDs in consumer configuration. The fixture does not grant access
to the experience or change publication settings. Launch data identifies a run; it grants no authority.

The [reference Player launcher](execution.md#published-player-execution) uses the signed-in account.
It currently supports one client per machine and requires an otherwise closed Player. Publishing
remains explicit; rerun the fixture build and publish after changing its mounted source. A Player run
uses published code, not files that changed locally afterward.

## Open Cloud

```sh
lute run tools/run.luau --entry examples/platform-entry.luau --host open-cloud \
  --cloud examples/open-cloud-transport.luau --universe-id U --place-id P --place-version V
```

The caller module owns credentials and policy (the example reads one key from its process environment
and allows only the Open Cloud origin); Verify never reads them. `--case` and `--deadline` behave as
for other hosts, the latter bounding polling. The published place version must already contain the
mounted framework and entry. The report, exit status and evidence are the ordinary ones, and the
command prints the task path, delivery, state and measured timing. A timeout prints the task path and
does not cancel; reconcile it with `session.reconcile(handle)` rather than resubmitting. See
[Open Cloud execution](execution.md#open-cloud-execution) for guarantees and limits.

## Launch or attach

By default `--host studio` launches a disposable Studio on a copy of an XML place and closes it.
Programmatic callers can instead pass `attach` to `Lute.platform.run` with `host = "studio"` to run the
same entry in a Studio that is already open:

```luau
Lute.platform.run {
	host = "studio",
	entry = "examples/platform-entry.luau",
	context = "Client",
	attach = {
		studioId = openStudioId,
		authorize = function(request) return { ok = true } end,
	},
}
```

Attach shares the developer's open Studio: there is no isolation, `players` is unsupported, and no
place is built or copied. The caller owns authorization (the required `authorize` hook sees every
request before it is sent), which place is open and whether the entry is mounted in it. Verify starts
play, runs, captures if asked and returns the Studio to its prior mode, but never closes it. The
command-line runner does not attach. See [Attached Studio](execution.md#attached-studio).

## Mounting and custom hosts

`Lute.place.build({ output, roots, modules?, clientSource?, serverSource?, rootName? })` builds an XML
fixture with a floor and spawn. It follows literal relative and `@self` imports, mounts the dependency
closure and rejects dynamic/external imports. It does not compile arbitrary package systems or replace
an application's place build. Use `moduleExpression(path, rootName?)` to reference a mounted module.

For an existing game fixture, mount under `ReplicatedStorage.VerifyModules`, or use the lower-level
[Studio host](execution.md#native-studio-execution) with your own bootstrap. Lower-level workers and
hosts remain available for custom discovery, scheduling and launch environments; they produce the
same cases and reports.
