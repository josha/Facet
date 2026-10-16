# Tools.verify

Check application types, usage, live layout and input on five devices.

Run `lute run tools/facet verify --tap Shop`. Use `--device desktop` to focus
one device. Without it, the command checks desktop, phone portrait, phone
landscape, tablet and console. Each tap follows the previous tap on that
device. Use `--tap Close` before opening another panel.

The command builds the project and owns one Studio session. It closes that
session when the run finishes. It does not control other open Studio sessions.
Console preview uses gamepad selection and the ten-foot environment. A preview
is live engine evidence, not a physical device test.

Audit output groups repeated findings. The full `report.txt`, interface dumps
and captures are under `--out` (default `artifacts/facet-verify`). Use
`--verbose` for every finding. A failed or missing tap, capture, type check,
build, or high or medium audit finding gives exit code 1.

`--static` checks types, usage and build, and reports that it skipped Studio.
`--dump FILE --device ID` audits saved evidence and does not prove current
behavior. For full type errors, run `lint --types --verbose`.

Open:

- [Types.reactive](Types.reactive.md)
- [Tasks.safe-layout](Tasks.safe-layout.md)
