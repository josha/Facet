# Shell cwd persists across tool calls — repo-root-relative paths can nest-create trees

Observed 2026-07-19: the session shell's cwd was left at `GameStudio/ui/LuauUI` by an earlier `cd`; later commands using `GameStudio/ui/LuauUI/...`-relative paths created a nested `GameStudio/ui/LuauUI/GameStudio/ui/LuauUI/` tree and operated on the wrong copy (first Fusion vendor landed there while the real tree kept a stale broken transform).

**Rule:** in this workspace, always use absolute paths in shell commands (or `cd` explicitly at the start of the same command), and after any path surprise run `pwd` before trusting relative output.
