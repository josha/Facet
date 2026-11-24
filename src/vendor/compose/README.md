# Compose dependency

This directory is a generated, read-only copy of upstream Compose.
`pkg.luau` pins Compose as a development dependency and `pkg.lock.luau` locks
the exact commit. `lute pkg install --vendor` installs it into `.lpm/`, and
`lute run tools/facet sync compose` copies its `src/core`, `src/roblox`,
`src/design`, `src/design-editor` and `LICENSE` here and its agent skill into
`skills/compose/`. There are no local patches. Do not edit these files.

Roblox require-by-string resolves only relative paths, `@self` and `@game`, so
the shipped library and every consumer that copies Facet need this relative copy.

```sh
lute pkg install --vendor
lute run tools/facet sync compose --check   # fail if any file differs from the installed package
lute run tools/facet sync compose           # copy the installed package
```

The vendor check runs `--check`, so a local change to the copy cannot land.

## Changing the pin

Move the `compose` revision in `pkg.luau`, run `lute pkg install --vendor` and
`lute run tools/facet sync compose`, set `COMPOSE_COMMIT` in `src/init.luau` and
name the commit in `THIRD_PARTY_NOTICES.md`. Then run `lute run tools/facet gate full`.

Relative links in the copied skill that point outside the skill directory are
changed to links to the locked commit on GitHub.
