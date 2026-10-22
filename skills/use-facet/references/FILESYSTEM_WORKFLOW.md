# Filesystem workflow

Use this workflow only when the project uses saved source files and shell tools.
Keep the project's sync path. Do not transfer the same source through a second path.

Use `lute run tools/facet docs Map` to open the reference map.
Use `docs <path>` for one node and `docs --search TEXT` to find paths and
one-line summaries. Use `project [directory]` for file discovery.

In a filesystem project, run `lute run tools/facet verify --static` and fix
its errors. Check the first live mount with `verify --device desktop --tap TEXT...`.
The live command runs strict types, usage lint, a Rojo build, audit and screenshots.
It builds and opens the saved project; do not copy source into Studio first.
Run one live check at a time and wait for its verdict before editing or starting
another. A returned process handle means the check is still running. Poll that
handle; changing `--out` does not make a competing Studio check useful.
Give one `--tap` for each control in the path to a screen. Without `--device`,
it uses one capture session across all five devices. It prints only problems
and screenshot paths.
During repairs, use `--device ID` to check the affected device. Run one complete
final sweep without `--device`. Use the printed `verify --report` queries to
read findings. Add `--step ID` for one capture. Do not read the full report.
Inspect those screenshots and fix high and medium findings. Repeat checks only
after changes or an unresolved problem; separate audit and preview calls are
not needed for the same screens. Do not read dump files. If Studio is
unavailable, report that limit once and use `verify --static`.

The tools remove a UTF-8 BOM from application Luau files before engine tools
read them. In Windows PowerShell 5.1 use `Set-Content -Encoding utf8`.
