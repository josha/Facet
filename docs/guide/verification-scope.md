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

The unit fixture loads Verify's bundled reflection capture. The Verify pin fixes
its version. Events and methods keep their captured class ownership. Normal
writes keep the captured property types and access restrictions. Cases supply
engine-owned values with `engine.environment.poke`. Unit GUI roots start with
zero geometry until a case supplies measurements. This fixture does not run
layout or text measurement. Input starts with no history, held keys or connected
gamepads. Cases supply the input history that their focus assertions require.

The Facet unit fixture supplies zero GUI insets. Its `GetStyled` fake reads
the raw property, and its styled property signal uses the property change
signal. Individual tests can supply specific styled values or inset behavior.
These fixtures do not prove StyleSheet resolution or native safe areas.

The `native_live_primitives` spec also runs five original Studio geometry
cases with Verify's computed layout. It checks Screen/VStack padding and gap,
grid cells and gaps, ZStack alignment, stack distribution and weighted fill.
The `native_live_contracts` spec adds 33 original live cases for text geometry,
frame stability, lifecycle, styles, grids and content. Together these specs
run 38 original live cases. They use Verify's bounded text model: 18 captured
font faces, integer sizes 1–100, Latin letters, digits, spaces and newlines.
Unsupported shaping and text modes raise errors. Upstream Verify checks
348 shared text layout configurations against Studio.

The Verify pin also models wrapped lists and fixed-size GUI aspect constraints.
Upstream checks 1,164 shared layout configurations and a mutation sequence
against Studio and the double. Automatic-size objects with aspect constraints
and individual aspect-constrained grid cells remain unsupported. Hierarchy selectors
and phantom UI modifiers have shared Studio/double assertions. Relative sizes
under automatic parents have 444 shared configurations and an eight-stage
mutation sequence. The model supports bounded final sizes. Growing feedback,
padded relative positions and constrained automatic parents with relative
children remain unsupported.

The primitive spec also loads every committed live source and registers its
cases in the double.
Registration does not prove case behavior. A planted gap regression must fail
the original assertion. These cases prove the selected model behavior. They
do not replace Studio evidence. Scrolling canvas/window geometry and the
remaining input, device and style mechanisms are outside this selection.
See [the live CI scope](../../tools/studio/CI.md).

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

The Verify gate records selection, failure, unsupported work and deferral.
The release tier requires complete evidence with no deferrals. Running every
selected command does not establish fresh Studio evidence for every control.

Benchmark timing budgets require the reference host. Elsewhere that producer
is deferred, not passed. Paired CI timing compares the same workload on each
platform. Instrumented resource checks and native frame observations answer
different questions. See [performance](performance.md).

Use [Contributing](../../CONTRIBUTING.md) for current commands. Report baseline
failures separately from regressions and state any untested behavior.
