# Public tree reproducibility (DR-25) — measured 2026-08-31, corrected same day

The first record of this proof claimed build hashes it never captured: the
extracted trees have no git repository, and the model builder refused to stamp
a commit. That was a real fresh-tarball defect (GitHub's Download ZIP is a
git-less consumer), fixed by stamping the deterministic constant
`unversioned-source` when no repository exists — publish guards still demand
real git. The numbers below were then actually captured.

Candidate-at commit: 3fcb5b2 (patched builder copied into the extracts).

| Proof | Result |
|---|---|
| `git archive` extracted twice | byte-identical (`diff -r` clean; whole-tree sha256-of-sha256s `f15eada3bd42a33d…` both times) |
| Model built in extract one | `1249298712fe3e302f3d17e4d599358302662fd7d96b267dbf6cf3ee2cae8e6a` |
| Model built in extract two | `1249298712fe3e302f3d17e4d599358302662fd7d96b267dbf6cf3ee2cae8e6a` — **identical to extract one** |
| Model rebuilt twice in the working repository | `9ab9c5a44f5e6112e1abebb0f97cc6e0c900bfb3489507f7a2ec2bd30ebf606e` / `9ab9c5a44f5e6112e1abebb0f97cc6e0c900bfb3489507f7a2ec2bd30ebf606e` — identical to each other |
| Extract build vs repository build | differ, by design: the `SourceCommit` attribute is `unversioned-source` in a git-less tree and the real commit in the repository — the one documented, intentional difference |

Re-run at the final candidate commit by repeating these commands verbatim.
