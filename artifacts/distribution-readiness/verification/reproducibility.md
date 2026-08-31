# Public tree reproducibility (DR-25) — measured 2026-08-31

Candidate-at commit: 3fcb5b267dd2c9d5f94cbc11f5f64b1297269edd. `git archive` extracted twice to independent
directories: byte-identical (`diff -r` clean; whole-tree sha256-of-sha256s
equal: f15eada3bd42a33d336ddf27a9fc36f3fde79b7fc2020b79df7df801be9a24d9). `tools/build_model.sh` run in each extract:
both produce the same `build/Facet.rbxm` sha256 (values above in the stage
log), matching the main tree's build. No nondeterminism observed; the one
documented nondeterministic input (none) is therefore an empty list. Re-run at
the final candidate commit by repeating these commands verbatim.
