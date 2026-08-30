# Contributing to Facet

Facet is a Roblox user-interface library written in Luau. This page is the
contributor's route: how to set the toolchain up, how to decide where a change
goes, what to run before you propose it, and what a good change looks like when it
arrives.

If you are here to *use* Facet rather than change it, read
[the guide](docs/guide/README.md) instead. If you are an automated coding agent,
read [`AGENTS.md`](AGENTS.md) first; it routes to the same documents in the order
an agent needs them.

## 1. Set the toolchain up

Facet pins its tools in [`rokit.toml`](rokit.toml) and installs them with
[Rokit](https://github.com/rojo-rbx/rokit), a Roblox toolchain manager.

```sh
rokit install                 # Rojo, luau-lsp, Lune, and StyLua at the pinned versions
python3 --version             # 3.9 or newer; several checks are Python
tools/doctor.sh               # verifies the toolchain and the library invariants
```

Four tools do the work.

- **Lune** runs the test suite and every Luau checker. Facet's decision layer is
  engine-free, so the suite needs no Roblox process.
- **Rojo** turns the source folder into an instance tree for Roblox Studio, and
  builds the example places and the distributable model.
- **StyLua** formats Luau. Formatting is checked, not negotiated.
- **Python 3** runs the checkers that read the tree as text.

Run `tools/doctor.sh` first whenever something behaves strangely, and before you
conclude that a build failure is a code problem.

## 2. Decide where the change goes

[`docs/MAINTAINERS.md`](docs/MAINTAINERS.md) is the map. It answers one question —
where does a change go, and what proves it — for every area of the library, and it
is checked against the tree, so it does not rot.

Then follow the playbook for the kind of change you are making. Each one is a
numbered procedure where every step has a command and a pass condition:

| You are adding | Playbook |
|---|---|
| a composite control | [`docs/extending/new-control.md`](docs/extending/new-control.md) |
| a new leaf element class | [`docs/extending/new-primitive.md`](docs/extending/new-primitive.md) |
| image-driven paint for an existing control | [`docs/extending/skinned-control.md`](docs/extending/skinned-control.md) |
| a theme package | [`docs/extending/new-theme.md`](docs/extending/new-theme.md) |
| the use of a Roblox class or property | [`docs/extending/new-engine-feature.md`](docs/extending/new-engine-feature.md) |
| a place the solved tree materializes | [`docs/extending/new-render-target.md`](docs/extending/new-render-target.md) |
| a platform or interaction mode | [`docs/extending/new-platform-mode.md`](docs/extending/new-platform-mode.md) |

[`docs/reference/constitution.md`](docs/reference/constitution.md) governs anything
the playbooks do not cover. It is the rulebook the library holds itself to, with
every approved exception named.

## 3. Verify what you changed

Verification runs in four named tiers through one command:

```sh
tools/verify.sh affected     # the smallest safe set for the files you changed
tools/verify.sh fast         # the inner-loop tier
tools/verify.sh full         # every deterministic check, exactly once
tools/verify.sh release      # full, plus the build, package, and evidence producers
```

Which one to use:

- **affected** or **fast** while you work. Fast is the whole deterministic spine
  minus the slowest files.
- **full** before you propose a change. This is the tier a reviewer expects to see
  a result line from.
- **release** belongs to the maintainer cutting a release. It runs the producers
  that touch builds, packages, and recorded evidence.

Affected and fast output is not full evidence, and the tool says so: both print a
banner, and the full and release readers refuse a fast tier's results. Do not
report a fast run as if it were a full one.

Two flags are worth knowing. `--explain` prints which producers were selected,
why, and why a reused result was allowed to stand. `--rerun <id>` ignores the
stored result for one producer and runs only that, which is the loop to use while
you fix a failure.

Two loops sit underneath the tiers and are worth knowing:

```sh
lune run tests/run_one <spec-name>   # one spec file, for the edit-and-run loop
./run-tests.sh                       # the complete suite, the way it has always run
./run-tests.sh --fast                # the same list minus the slowest files
```

`run_one` is also how you watch a new check **fail** before you trust it. This
repository asks for that every time: a check nobody has seen fail is decoration.

Formatting and the text checks:

```sh
stylua --check src tests tools bench examples
python3 tools/check_doc_style.py       # clear-writing rules on the documents people read
python3 tools/check_brand_drift.py     # naming and product-language rules
```

**The product-language rule matters and is easy to trip.** Facet explains itself in
Roblox and Facet terms. Another user-interface framework, its vendor, that vendor's
operating systems, or its sample applications may not be the *name* of a Facet
feature or the *reason* for one. One document is exempt: the short guide that
compares Facet with the alternatives, which exists precisely to make that
comparison. Everywhere else, describe the behavior.

**The clear-writing rule** keeps the documents a reader is expected to read in
order plain and direct: one instruction per numbered step, every acronym expanded
once before it is used, and no repository-internal shorthand on a public page.

## 4. Tests come first, and they must fail first

Facet's standard is not "there is a test". It is "the test was seen to fail for the
reason you expect, before the fix existed". Write the covering spec, run
`lune run tests/run_one <spec>`, watch it go red, then make it green.

Every new spec file must be registered in `tests/run.luau`. An unregistered spec
is a silent zero, and the registration checker fails a run that has one.

## 5. What a good change looks like

- **One concern per change.** A refactor and a behavior change in the same commit
  cannot be reviewed or reverted separately.
- **A subject line that is one plain sentence** saying what the change does, in
  the present tense.
- **Documentation updated in the same change.** A new public property that is not
  in [`docs/reference/api.md`](docs/reference/api.md) fails a checker, and a new
  capability that is not in the [guide index](docs/guide/README.md) catalog fails
  another.
- **No new public surface without a decision record.** If a change alters what the
  library promises, add an architecture decision record under
  [`docs/adr/`](docs/adr/) that says what was chosen and what was rejected.
- **Both consumer routes stay working.** Some people use Facet through Rojo from a
  Git checkout; others install the built model or the Roblox Package into Studio
  with no toolchain at all. A change that assumes a file sync breaks the second
  group. [Guide 8](docs/guide/08-without-rojo.md) is what that group reads.

## 6. Reporting a problem

Open an issue using the templates in `.github/ISSUE_TEMPLATE/`. A bug report needs
the smallest reproduction you can get to, what you expected, what happened, the
value of `Facet.VERSION`, and the device and input class you saw it on. A security
problem is not an issue: follow [`SECURITY.md`](SECURITY.md).

## 7. What is not a contributor's job

Facet has a production consumer game that the maintainer keeps in step with the
library, release by release. Keeping that game current is the maintainer's work,
not yours. Propose the framework change on its own merits; the maintainer carries
it downstream.

Publishing the Roblox Package, cutting a release, and anything that touches a
Roblox account or an application key are likewise maintainer operations. They need
credentials that are never in this repository.

## 8. License

By contributing you agree that your contribution is licensed under the MIT
License, the same terms as the rest of Facet. See [`LICENSE`](LICENSE).
