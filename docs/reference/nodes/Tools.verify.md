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

The command prints the expected duration before the checks start. Wait for
the verdict. Each device has one capture summary with a project-relative
directory, such as `desktop: 8 captures in artifacts/facet-verify/live/captures/desktop`.
Every capture is kept. Audit output groups repeated findings. The verdict is
`verify: PASS` or `verify: FAIL`.

The full `report.txt`, interface dumps and captures are under `--out`
(default `artifacts/facet-verify`). Static and total times are in `timings.json`.
Live phase times are in `live/timings.json`.
Read findings with `lute run tools/facet verify --report --device desktop
--rule text-fit`. Use the rule ID from the output. Add `--step 2-shop` for one
capture. Use `--out DIR` for another saved run. Each query prints at most 4096
bytes. If it has more findings, repeat it with the printed `--page N`.
Capture IDs use `device/step`; their images are in
`live/captures/<device>/<step>.png` under `--out`. The default output ends with
an exact query for each failing device and rule. Queries do not start Studio
or change the saved report. Do not read the full report during repairs.
Use `--verbose` for each capture path and every finding. A failed or missing
tap, capture, type check, build, or high or medium audit finding gives exit code 1.

`--tap TEXT` taps a visible ScreenGui element whose text contains TEXT, at
the centre of its visible rectangle. Text in a SurfaceGui or BillboardGui is
not a tap target. When more than one element matches, it taps the one nearest
the top of the screen, then the one nearest the left edge. Give each action its
own visible name. A text inside a Button, such as its `caption`, taps the
Button that holds it.

Each tap waits for stable layout before capture. Use `--wait SECONDS` to set
an explicit delay after each tap.
If the interface does not mount or a tap fails, the device stops its dependent
steps and keeps the root failure capture. Other devices still run.

During repairs, use `--device ID` for focused checks. After the repairs, run
one complete final sweep without `--device`. For option errors, use
`lute run tools/facet docs <Control>.props` instead of reading package source.

`--static` checks types, usage and build, and reports that it skipped Studio.
`--dump FILE --device ID` audits saved evidence and does not prove current
behavior. For full type errors, run `lint --types --verbose`.

Open:

- [Types.reactive](Types.reactive.md)
- [Tasks.safe-layout](Tasks.safe-layout.md)
