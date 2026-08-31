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

## The second documented nondeterminism: place files carry a build TIME

`tools/build_places.sh` and `tools/build_reference_places.sh` stamp each place
they emit with a build identity AND a build clock, into a Workspace attribute the
showcase renders in its own settings panel. That stamp is deliberate and it was
bought with a real device session: on 2026-08-16 a showcase was tested 5 h 41 m
after the commit it was meant to prove, the tester correctly reported a missing
feature, and the build in their hands simply predated it — with nothing on screen
able to say so.

The consequence for this document is that **the fourteen tracked `.rbxl` under
`examples/places/` are not byte-reproducible and are not meant to be.** Two
builds of the same source differ in the stamp, and that is the whole point of the
stamp. They are excluded from the reproducibility claim above, which is about the
model and the extracted tree.

It has a second consequence, and it is why this section exists rather than a
footnote: a producer that rewrites fourteen tracked files must never run in an
inner loop. Measured by a fresh agent on a pristine clone, 2026-08-31: the
`affected` tier selected both builders off a README edit, because they declared
the same whole-tree input set every scanner shares, and left the working tree
dirty for a change that could not have touched a place. Their inputs are now the
trees that actually feed a place, and `tiers.affected = false` in the graph keeps
them out of the inner loop entirely while `full` and `release` still build and
judge them.
