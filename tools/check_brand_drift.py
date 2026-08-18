#!/usr/bin/env python3
"""check_brand_drift — the retired brand may not reappear in maintained trees.

The framework's pre-rename name is matched case-insensitively in every separator
form over: (a) tracked files of the framework repo, paths and contents, except
the frozen-evidence trees; (b) tracked files of the Rascal Rally repo; (c) the
current-facing studio surfaces outside both repos; (d) the serialized object
names of every buildable place (each Rojo project built to XML and scanned),
because a binary .rbxl is LZ4-chunked and a byte grep over it proves nothing.

Every permitted match lives in the ALLOWLIST below with a reason and a removal
rule — the list is the guard's private match data, not documentation. A match
outside the allowlist fails the run and prints file:line.

`--selftest` proves the guard can fail: it plants one old-name content line and
one old-name file path inside scanned directories, requires both scans to go
red, removes them, and requires the restored tree to pass. It also plants an
allowlisted pattern in a NON-allowlisted file to prove the allowlist is scoped
to its paths.

Usage:  python3 tools/check_brand_drift.py [--selftest] [--skip-builds]
Exit 0 = clean; 1 = drift found; 2 = environment failure (e.g. rojo missing).
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STUDIO_ROOT = os.path.abspath(os.path.join(REPO, "..", "..", ".."))
RR = os.path.join(STUDIO_ROOT, "games", "RascalRally", "code")

BRAND = re.compile(r"luau[\s._-]?ui", re.IGNORECASE)

# THE THEME-AUTHORING TAG VOCABULARY (controller ruling R11, wave R5). The public
# tags a theme package selects on were still `luau-*` / `luau-slot-*` under a
# framework named Facet, and `BRAND` structurally CANNOT see them (ARCH-16):
# there is no "ui" after "luau", so no amount of separator tolerance reaches
# `luau-chrome-panel`. The tags renamed outright to `facet-*` — no alias, no dual
# vocabulary, because the repository is pre-public with zero external theme
# authors and this was the only moment the rename was free.
#
# The negative lookahead names the three LUAU-THE-LANGUAGE terms that are not the
# retired brand at all and never were: the analyser, the language server, and one
# lesson filename. They are excluded structurally rather than allowlisted by path,
# because they are legitimate everywhere and an allowlist entry would have to be
# repeated for every file that ever mentions the toolchain.
# Every tag is lowercase, so the pattern is CASE-SENSITIVE: "Luau-side",
# "Luau-authoritative" and "a Luau-call-count win" are prose about the LANGUAGE
# and appear in a dozen ADRs. The four excluded stems are the Luau toolchain and
# two lesson filenames about Luau syntax — not the retired brand, and legitimate
# in any file, which is why they are excluded structurally instead of by path:
#   lsp                              the Luau language server
#   analyze                          the Luau analyser binary
#   execution-session                a Roblox Open Cloud API scope name
#   interpolated-strings-single-line docs/lessons/… (a Luau string-syntax trap)
#   require-by-string-init-self      docs/lessons/… (a Luau require trap)
TAG = re.compile(r"\bluau-(?!lsp\b|analyze\b|execution-session\b"
                 r"|interpolated-strings-single-line"
                 r"|require-by-string-init-self)")

# every pattern the old-brand profile matches, in report order
PROFILE = (BRAND, TAG)

# Frozen-evidence trees: never scanned. Their reason is structural (the plan's
# immutable-evidence class), not per-file.
EXCLUDED_TREES = (
    "artifacts/",          # gate evidence records the name it was earned under
    "docs/superpowers/",   # the frozen original design spec
    ".superpowers/",       # controller scratch, git-ignored
)

# Rascal Rally dated history: append-only or per-mission records that keep the
# name they were written under. Current-facing RR docs ARE scanned.
RR_DOC_HISTORY = ("docs/missions/", "docs/playtests/", "docs/DECISIONS.md")

# (path-prefix-or-exact, pattern-that-may-match, reason, removal rule)
ALLOWLIST = [
    ("docs/adr/ADR-0036-facet-rename.md", BRAND,
     "the rename ADR is the one document that names both brands",
     "permanent (ADRs are history)"),
    ("docs/adr/ADR-0036-facet-rename.md", TAG,
     "…and it now records that the theme tags moved later, which means quoting them",
     "permanent (ADRs are history)"),
    ("docs/adr/ADR-0038-theme-tag-vocabulary.md", TAG,
     "the tag-rename ADR is the one document that names both tag vocabularies",
     "permanent (ADRs are history)"),
    ("docs/adr/ADR-0038-theme-tag-vocabulary.md", BRAND,
     "it names the retired product once, explaining why BRAND could not see the tags",
     "permanent (ADRs are history)"),
    ("tools/lune/gate_manifest.luau", re.compile(r"artifacts/", re.I),
     "run/note lines that quote files under artifacts/ quote frozen evidence",
     "when the quoted prior-gate rows are archived (Step 14 gate simplification)"),
    #[[ SCOPED TO THE SENTENCE, NOT TO THE FILE (R5 review §2-1). The first
    #   version of these two entries reused the profile patterns themselves as
    #   their `pat`, which makes `allow()` tautological: ANY `luau-*` tag
    #   anywhere in this ~4,000-line, every-wave-edited manifest was excused.
    #   Proved by planting an unrelated tag 4,000 lines from the note and
    #   watching the checker still PASS. The patterns below match only the two
    #   literal clauses of the naming-adr-implemented note that have to name the
    #   retired vocabulary, so a tag anywhere else in the file is caught. ]]
    ("tools/lune/gate_manifest.luau",
     re.compile(r"renamed the public theme-authoring tags luau-\*/luau-slot-\* to facet-\*/facet-slot-\*"),
     "the naming-adr-implemented note states WHICH tag family ADR-0038 retired; a gate note "
     "that cannot name the old vocabulary cannot record that it moved",
     "permanent (the note is the gate's own history, like the ADR it cites)"),
    ("tools/lune/gate_manifest.luau",
     re.compile(r"BRAND is luau\[\\\\s\._-\]\?ui and there is no ui after luau in a tag"),
     "the same note quotes this checker's own BRAND pattern to explain why 346 surviving "
     "tags were structurally invisible to it",
     "permanent (same reason)"),
    ("tools/check_perf_gate_evidence.py", BRAND,
     "reads frozen capture artifacts whose schema strings predate the rename",
     "when those capture schemas are re-recorded under Facet"),
    ("tools/check_device_captures.py", BRAND, "same frozen-capture schema rule",
     "same"),
    ("tools/check_perf_captures.py", BRAND, "same frozen-capture schema rule",
     "same"),
    ("tools/check_sf_rows.py", BRAND, "same frozen-capture schema rule", "same"),
    ("tools/check_xp_matrix.py", BRAND, "same frozen-capture schema rule", "same"),
    ("tests/theme_reference_packages.spec.luau", BRAND,
     "one comment records the schema-stamp re-pin (luauui-theme/1 -> facet-theme/1)",
     "when the theme schema next revs"),
    ("tools/lune/check_flat_baseline.luau", BRAND,
     "characterization entries quote the frozen 0.6.0 baseline's on-screen titles",
     "when the flat baseline is re-recorded under Facet"),
    ("tools/lune/theme_sync_cli.luau", BRAND,
     "dev CLI reads frozen theme-sync dumps stamped with the pre-rename schema",
     "when those dumps are re-recorded"),
    ("phases.json", BRAND,
     "the Step-13 phase title names the rename itself",
     "when Step-13 phase records are archived"),
    ("requirements.json", re.compile(r"2026-07-19-luauui-crossplatform", re.I),
     "citation of the frozen design-spec file by its real name",
     "Step 14 private-archive move"),
    ("docs/INVENTORY.md", re.compile(r"2026-07-19-luauui-crossplatform", re.I),
     "same frozen-spec citation", "same"),
    ("tools/check_brand_drift.py", BRAND,
     "the guard's own match data", "never (it IS the guard)"),
    ("tools/check_brand_drift.py", TAG,
     "the guard's own tag-pattern match data and its planted selftest tag",
     "never (it IS the guard)"),
    # Rascal Rally repo entries (paths relative to the RR repo, prefixed rr:)
    ("rr:src/client/FacetFlags.luau", BRAND,
     "dual-read fallback: the five pre-rename attribute names ARE the migration",
     "docs/migrations/facet-attribute-migration.md removal trigger"),
    ("rr:tests/facet_flag_migration.spec.luau", BRAND,
     "asserts the dual-read fallback by its real attribute names", "same"),
    ("rr:src/client/init.client.luau", BRAND,
     "one comment routes readers to the migration doc", "same"),
    ("rr:tests/run.luau", BRAND,
     "one comment explains the migration spec's fake workspace", "same"),
    ("rr:tests/facet_help_callout_contract.spec.luau", BRAND,
     "comment explains a pinned order that moved in the rename", "next re-pin"),
    ("rr:tests/facet_motion_and_scroll_contract.spec.luau", BRAND,
     "same comment rule", "next re-pin"),
    ("rr:tests/facet_theme_paint_contract.spec.luau", BRAND,
     "same comment rule", "next re-pin"),
    ("studio:games/RascalRally/docs/DECISIONS.md", BRAND,
     "append-only decision ledger; old entries keep the name they were written under",
     "never (append-only history)"),
    ("studio:games/RascalRally/docs/migrations/facet-attribute-migration.md", BRAND,
     "the migration manifest names the five attributes it migrates",
     "its own removal trigger"),
    # Studio surfaces outside both repos
    ("studio:games/RascalRally/docs/FACET_SETTINGS_PORT.md",
     re.compile(r"2026-07-19-luauui-crossplatform", re.I),
     "frozen-spec citation", "Step 14 archive"),
]


def tracked(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(f"check_brand_drift: FAIL_ENVIRONMENT git ls-files in {repo}")
        sys.exit(2)
    return out.stdout.splitlines()


def allow(scope_path, line_text, pattern):
    for path, pat, _reason, _removal in ALLOWLIST:
        if scope_path == path or scope_path.startswith(path.rstrip("/") + "/") \
           or scope_path == path:
            # An entry excuses a line when the entry's OWN pattern matches that
            # line — so a narrow entry (a frozen capture-schema string, a cited
            # spec filename) keeps its scope whichever profile pattern fired.
            # The BRAND shortcut is deliberately not extended to the tag half:
            # "this file may name the old product" is not "this file may keep a
            # `luau-*` theme tag".
            if pat.search(line_text) or (pat is BRAND and pattern is BRAND):
                return True
    return False


def scan_file(abs_path, scope_path, hits):
    base = os.path.basename(abs_path)
    allowed_path = any(scope_path == p or scope_path.startswith(p)
                       for p, *_ in ALLOWLIST)
    for pattern in PROFILE:
        if pattern.search(base) and not allowed_path:
            hits.append(f"{scope_path}: PATH carries the old brand")
            break
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                for pattern in PROFILE:
                    if pattern.search(line) and not allow(scope_path, line, pattern):
                        hits.append(f"{scope_path}:{n}: {line.strip()[:120]}")
                        break
    except OSError:
        pass


def scan_repo(repo, prefix, exclude, hits):
    for rel in tracked(repo):
        p = rel.replace("\\", "/")
        if any(p.startswith(t) or f"/{t}" in p for t in exclude):
            continue
        if prefix == "rr:" and any(p.startswith(t) for t in RR_DOC_HISTORY):
            continue
        if p.endswith((".rbxl", ".rbxm", ".png", ".jpg", ".gprx", ".pyc",
                       ".ttf", ".otf", ".webp")):
            continue  # binaries are proved through the built-XML scan instead
        scan_file(os.path.join(repo, rel), prefix + p if prefix else p, hits)


def scan_builds(hits):
    projects = [p for p in tracked(REPO) if p.endswith(".project.json")]
    rojo = os.path.expanduser("~/.rokit/bin/rojo")
    if not os.path.exists(rojo):
        print("check_brand_drift: FAIL_ENVIRONMENT rokit rojo missing")
        sys.exit(2)
    for proj in projects:
        with tempfile.NamedTemporaryFile(suffix=".rbxlx", delete=False) as tf:
            tmp = tf.name
        try:
            r = subprocess.run([rojo, "build", proj, "-o", tmp], cwd=REPO,
                               capture_output=True, text=True)
            if r.returncode != 0:
                hits.append(f"{proj}: rojo build failed: {r.stderr.strip()[:160]}")
                continue
            with open(tmp, encoding="utf-8", errors="replace") as fh:
                for n, line in enumerate(fh, 1):
                    # serialized NAMES only: property lines carrying name attrs
                    if 'name="Name"' in line and any(
                            p.search(line) for p in PROFILE):
                        hits.append(f"{proj} (built XML) line {n}: {line.strip()[:120]}")
        finally:
            os.unlink(tmp)


def studio_surfaces(hits):
    surfaces = [
        os.path.join(STUDIO_ROOT, "CLAUDE.md"),
        os.path.join(STUDIO_ROOT, "games/RascalRally/CLAUDE.md"),
    ]
    for root in (os.path.join(STUDIO_ROOT, ".claude/agents"),
                 os.path.join(STUDIO_ROOT, "GameStudio/specialists")):
        for dirpath, _d, names in os.walk(root):
            surfaces += [os.path.join(dirpath, n) for n in names]
    docroot = os.path.join(STUDIO_ROOT, "games/RascalRally/docs")
    for dirpath, dirs, names in os.walk(docroot):
        dirs[:] = [d for d in dirs if d not in ("missions", "playtests")]
        surfaces += [os.path.join(dirpath, n) for n in names]
    for f in surfaces:
        if os.path.isfile(f):
            rel = "studio:" + os.path.relpath(f, STUDIO_ROOT)
            scan_file(f, rel, hits)


def run_scan(skip_builds=False):
    hits = []
    scan_repo(REPO, "", EXCLUDED_TREES, hits)
    scan_repo(RR, "rr:", (), hits)
    studio_surfaces(hits)
    if not skip_builds:
        scan_builds(hits)
    return hits


def selftest():
    probe_content = os.path.join(REPO, "src", "drift_probe_tmp.luau")
    probe_path = os.path.join(REPO, "tests", "luauui_probe_tmp.luau")
    probe_allow = os.path.join(REPO, "src", "core", "drift_probe_allow.luau")
    probe_tag = os.path.join(REPO, "src", "tag_probe_tmp.luau")
    probe_toolchain = os.path.join(REPO, "src", "toolchain_probe_tmp.luau")
    try:
        with open(probe_content, "w") as f:
            f.write("-- planted: LuauUI must be caught here\nreturn {}\n")
        with open(probe_path, "w") as f:
            f.write("return {}\n")
        # an allowlisted PATTERN outside its allowlisted PATH must still fail
        with open(probe_allow, "w") as f:
            f.write("-- planted: the luauui-theme/1 stamp outside its file\n")
        # the TAG half (R11): `luau-chrome-panel` carries no "ui" at all, so it is
        # invisible to BRAND and only the tag pattern can see it
        with open(probe_tag, "w") as f:
            f.write('local tag = "luau-chrome-panel"\nreturn tag\n')
        # ...and the three Luau-the-language terms must NOT be caught, or the
        # guard becomes a thing people route around
        with open(probe_toolchain, "w") as f:
            f.write("-- the repo runs no luau-analyze; luau-lsp is not installed\n")
        # planted files are untracked; scan them directly
        hits = []
        scan_file(probe_content, "src/drift_probe_tmp.luau", hits)
        scan_file(probe_path, "tests/luauui_probe_tmp.luau", hits)
        scan_file(probe_allow, "src/core/drift_probe_allow.luau", hits)
        scan_file(probe_tag, "src/tag_probe_tmp.luau", hits)
        toolchain_hits = []
        scan_file(probe_toolchain, "src/toolchain_probe_tmp.luau", toolchain_hits)
        if len([h for h in hits if "drift_probe_tmp" in h]) < 1 \
           or len([h for h in hits if "PATH carries" in h]) < 1 \
           or len([h for h in hits if "drift_probe_allow" in h]) < 1 \
           or len([h for h in hits if "tag_probe_tmp" in h]) < 1 \
           or toolchain_hits:
            print("check_brand_drift: SELFTEST FAIL — a planted violation survived, "
                  "or a Luau-toolchain mention was caught as brand drift")
            print("\n".join(hits + [f"toolchain: {t}" for t in toolchain_hits]))
            return 1
    finally:
        for p in (probe_content, probe_path, probe_allow, probe_tag,
                  probe_toolchain):
            if os.path.exists(p):
                os.unlink(p)
    clean = run_scan(skip_builds=True)
    if clean:
        print("check_brand_drift: SELFTEST FAIL — restored tree not clean:")
        print("\n".join(clean[:20]))
        return 1
    print("check_brand_drift: SELFTEST PASS — planted content, planted path, "
          "planted `luau-*` theme tag, and out-of-scope allowlist pattern each "
          "caught; `luau-analyze`/`luau-lsp` deliberately not caught; restored "
          "tree clean")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    hits = run_scan(skip_builds="--skip-builds" in sys.argv)
    if hits:
        print(f"check_brand_drift: FAIL — {len(hits)} old-brand match(es) outside "
              "the allowlist:")
        for h in hits[:60]:
            print("  " + h)
        if len(hits) > 60:
            print(f"  … and {len(hits) - 60} more")
        sys.exit(1)
    print("check_brand_drift: PASS — no old-brand drift outside the recorded "
          "allowlist (reasons + removal rules live beside each entry)")


if __name__ == "__main__":
    main()
