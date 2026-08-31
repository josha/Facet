# Repository rename record — DR-34 evidence

**Executed 2026-08-31 by the director with the owner's checkpoint approval
(answer #2, this session), after creating the disaster mirror.**

| Step | Result |
|---|---|
| Pre-mutation mirror | `git clone --mirror https://github.com/josha/LuauUI.git ~/Facet-premutation-mirror-20260831.git` — 193 MB, `main` = `27c0afd…` (exactly what GitHub held), stored OUTSIDE Dropbox |
| Mutation | `gh api -X PATCH repos/josha/LuauUI -f name=Facet` |
| Identity preserved | response + re-read: `full_name: josha/Facet`, `id: 1320732857`, `node_id: R_kgDOTrjIuQ`, `private: true`, `default_branch: main` — same repository id as the freeze recorded |
| Redirect | `git ls-remote https://github.com/josha/LuauUI.git HEAD` answers `27c0afd…` through GitHub's redirect (do not rely on it long-term; never reuse the old name — reuse kills it) |
| Local remote | `git remote set-url origin https://github.com/josha/Facet.git`; `git fetch origin` clean; `main` is 99 commits ahead of `origin/main`, unpushed by design (the rewritten candidate is what eventually gets pushed, so the ordinary push never happens) |
| Links | the maintained tree carries the old URL nowhere (the old-name drift guard is green); `package/facet-package.json` and every doc already say `josha/Facet` |
| Rollback | Settings → rename back to `LuauUI` (restores the old name, removes the new-name redirect); disaster copy = the mirror above |
