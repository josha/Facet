# Clean-clone proof (RC-6) — 2026-08-17

`git clone` of GameStudio/ui/Facet (HEAD b230b87) into a fresh temp tree ending
`GameStudio/ui/Facet`, with the old folder absent everywhere:

| Check | Result |
|---|---|
| Symlinks in the clone root | 0 (`find . -maxdepth 1 -type l`) |
| Full suite from the clone | `6188 passed`, exit 0 (cold — no cache carried) |
| `rojo build examples/showcase.project.json` from the clone | exit 0, `Facet-Showcase` project, 2,957,478 bytes |
| Old path | `GameStudio/ui/LuauUI` does not exist (`ls` errors) |
| Both Rascal Rally projects vs the real new path | `rojo build` exit 0 each (recorded in rename/commands.md by the rename task; RR suite 3374 green against the moved tree) |

The clone ran with no access to the original working tree's untracked files, so
nothing in build or test depends on unversioned state, symlinks, or the old
folder name.
