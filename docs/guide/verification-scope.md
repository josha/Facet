# Verification scope

The current suite is the evidence. A passing run proves only the cases and
producers selected. A focused run is not full evidence.

## Headless

`tests/plan.json` lists spec sources exactly once. Verify registers their cases
and reports assertions, source revision, selected tier and outcomes. The plan
producer rejects missing, duplicate or incorrectly mapped sources.

The native engine double checks control policy, state, bindings and resource
ownership. Reflection metadata describes engine classes; it does not supply
native behavior. Read the selected assertions rather than treating case count
as coverage.

The Facet unit fixture supplies zero GUI insets. Its `GetStyled` fake reads
the raw property, and its styled property signal uses the property change
signal. Individual tests can supply specific styled values or inset behavior.
These fixtures do not prove StyleSheet resolution or native safe areas.

## Live

Native geometry, text editing, scrolling, selection, hit testing and input need
live Studio evidence. Record the actual build and device. Wait for viewport and
CoreGui insets to settle before checking geometry, but do not discard later
geometry faults as startup.

Distinguish a changing content state from unstable geometry within a fixed
state. An indeterminate fill may move while its layout box and neighbors remain
stable. Exercise negative cases so the audit proves it detects actual faults.

Studio simulation does not prove physical haptic output, thermals, battery
or device memory pressure. See [device verification](device-verification.md).

## Gate

Prepare the same dependencies used by CI before the full local run:

```sh
rokit install --no-trust-check
lute run tools/facet types prepare
lute run tools/facet gate full
```

The preparation command checks pinned tools, Git and Bash, generates Lute
typedefs and downloads both pinned Roblox definition files. It needs network
access for missing files and write access to the Lute typedef directory.
It fails before the expensive suite if these dependencies are unavailable.
A successful preparation is not verification evidence. Run the full gate
and fix its failures before publishing a completed change.

The Verify gate records selection, failure, unsupported work and deferral.
The release tier requires complete evidence with no deferrals. Running every
selected command does not establish fresh Studio evidence for every control.

Benchmark timing budgets require the reference host. Elsewhere that producer
is deferred, not passed. Paired CI timing compares the same workload on each
platform. Instrumented resource checks and native frame observations answer
different questions. See [performance](performance.md).

Use [Contributing](../../CONTRIBUTING.md) for current commands. Report baseline
failures separately from regressions and state any untested behavior.
