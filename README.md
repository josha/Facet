# Facet

Facet is a user-interface library for Roblox, written entirely in Luau. You hand
it a plain-data description of the screen you want, and it decides which real
objects to create, when to change them, and when to destroy them — you never
write `Instance.new("Frame")` or set a `Position` by hand. Layout, state, focus,
and adaptation are ordinary Luau, so a test can check them exactly without a
running engine, and a thin adapter edge turns the result into real Roblox user
interface through the engine's own scrolling, styling, and input. One
description adapts from a phone to a console without a per-device branch, and
every control it ships is reachable by pointer, touch, keyboard, and gamepad.

## Where the documentation is

| Document | What it is |
|---|---|
| [`docs/guide/README.md`](docs/guide/README.md) | **Start here.** The guide, written for a Roblox developer who has never seen this repository, meant to be read in order. It carries the capability catalog: every public capability the library ships, one line each, linked to its reference entry. |
| [`docs/reference/api.md`](docs/reference/api.md) | The exhaustive reference — every property, default, callback, and return value. |
| [`docs/reference/constitution.md`](docs/reference/constitution.md) | The rules anything added to this repository has to follow. |
| [`docs/extending/`](docs/extending/) | The playbooks, one per kind of addition: a control, a primitive, a theme, a skinned control, an engine feature, a render target, a platform mode. Each step has a command and a pass condition. |
| [`docs/adr/`](docs/adr/) | The decision records: what was chosen, what was rejected, and why. |
| [`docs/lessons/`](docs/lessons/) | Defects that cost real time, written up so the next person recognises the shape. |

## Running the tests

The suite is pure Luau and runs headless under [Lune](https://lune-lang.com/).
Run these from this directory:

```sh
./run-tests.sh                        # THE SUITE — every spec file. The only run that counts as green.
./run-tests.sh --fast                 # the inner-loop tier: the same list minus the slowest files.
lune run tests/run_one <spec-name>    # ONE spec file, for the edit-and-run loop.
```

`run_one` takes a spec name without its suffix, so `lune run tests/run_one table`
runs `tests/table.spec.luau` and nothing else. It is the loop to use while you
work, and the loop to prove a new check FAILS before you trust it. Neither
`run_one` nor `--fast` can produce a suite verdict: only the argument-free run
is green, and `tools/test.sh` refuses the other two transcripts.

## Checking the toolchain

```sh
tools/doctor.sh
```

It verifies the pinned toolchain and the library invariants, builds the showcase
place to prove the project file still maps the library, and writes
`artifacts/doctor.json`. Run it first whenever something behaves strangely, and
before you conclude that a build failure is a code problem.

## Seeing it run

- `examples/gallery/` is the showcase place: one place you publish once, with a
  picker that switches between every demo and every shipped theme on the device
  you are holding. Build it with
  `rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl`.
- `examples/gallery/examples/` holds the seven tutorial examples the guide
  teaches, smallest first.
- `examples/reference/` holds five complete reference applications, each built
  from nothing but the public surface.
