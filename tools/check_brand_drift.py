#!/usr/bin/env python3
"""check_brand_drift — two naming rules the maintained trees may not break.

RULE 1, the retired brand. The framework's pre-rename name is matched
case-insensitively in every separator form over: (a) tracked files of the
framework repo, paths and contents, except the frozen-evidence trees; (b)
tracked files of the Rascal Rally repo; (c) the current-facing studio surfaces
outside both repos; (d) the serialized object names of every buildable place
(each Rojo project built to XML and scanned), because a binary .rbxl is
LZ4-chunked and a byte grep over it proves nothing.

RULE 2, product-language independence. Facet explains itself in Roblox and
Facet terms. It may not use another user-interface framework, its vendor, that
vendor's operating systems, sample applications, or documentation domains as
the NAME or the REASON for a feature. The match list for that rule is VENDOR
below: private guard data, deliberately not product documentation. It scans the
framework repo only — the rule is about how FACET explains itself, and Rascal
Rally is a separate product with its own editorial policy. Two content
exceptions exist and no more:

  1. docs/reference/swiftui-parity.md, the one dedicated comparison document;
  2. a short comparison block inside docs/guide/**, delimited by the markers
     `<!-- comparison:begin -->` / `<!-- comparison:end -->`, capped at
     COMPARISON_MAX_LINES so it stays an aside rather than a contract.

Dated records are not scanned for rule 2 (VENDOR_HISTORY): accepted ADRs and
consumed wave plans are the evidence of a decision, and rewriting one falsifies
the record it exists to keep. Each carries its reason and its removal rule.

Every other permitted match lives in an allowlist with a reason and a removal
rule — the lists are the guard's private match data, not documentation. A match
outside them fails the run and prints file:line.

`--selftest` proves the guard can fail. For rule 1 it plants one old-name
content line and one old-name file path inside scanned directories, requires
both scans to go red, removes them, and requires the restored tree to pass; it
also plants an allowlisted pattern in a NON-allowlisted file to prove the
allowlist is scoped to its paths. For rule 2 it plants one vendor word in src/
and one in docs/guide OUTSIDE a marked block, requires both to redden, plants a
third INSIDE a marked block and requires it to pass, then restores and requires
the tree to pass.

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
BRAND_PROFILE = (BRAND, TAG)

#[[ ---- RULE 2: THE VENDOR PROFILE ----------------------------------------
#   Facet must explain itself in Roblox and Facet terms. Another framework, its
#   vendor, that vendor's operating systems, its sample applications, or its
#   documentation domains may not be the NAME or the REASON for a Facet
#   feature. Write `compact touch`, `desktop pointer`, `glossy`, `flat`, or the
#   exact Facet API name instead.
#
#   The patterns are word-bounded and case-insensitive. Two deliberately narrow
#   choices: `mac catalyst` rather than a bare `catalyst`, and sample-application
#   names only where the name is distinctive. One sample application is called
#   `Landmarks`, which is also an ordinary English noun this repository uses for
#   visual anchors in a scrolling rail, so it is deliberately NOT matched — a
#   guard that reports a homonym gets routed around. ]]
VENDOR = re.compile(
    r"\b(?:swift\s?ui|swiftui|swift)\b"
    r"|\bapple\b|\bcupertino\b"
    r"|\bios\b|\bipad\s?os\b|\bmac\s?os\b|\bos\s?x\b"
    r"|\bwatch\s?os\b|\btv\s?os\b|\bvision\s?os\b"
    r"|\biphone\b|\bipad\b|\bimac\b|\bmacbook\b|\bmac\b"
    r"|\bxcode\b|\buikit\b|\bappkit\b|\bcocoa\b|\bmac\s+catalyst\b"
    r"|\bsf\s?symbols?\b|\bsan\s?francisco\b|\bvoiceover\b|\btaptic\b"
    r"|\bcore\s+haptics\b"
    r"|\bbackyard\s+birds\b|\bfood\s+truck\b|\bfruta\b|\bscrumdinger\b"
    r"|\bhuman\s+interface\s+guidelines\b|\bhig\b"
    r"|developer\.apple\.com|apple\.com",
    re.IGNORECASE,
)

VENDOR_PROFILE = (VENDOR,)

# The earned gate ids that carry a retired stage name. Each is also a directory
# under artifacts/, which is frozen evidence and never rewritten.
GATE_IDS = re.compile(r"swiftui-parity-round\d|swiftui-reference-app-validation")

# The one dedicated comparison document (content exception 1). Its PATH names
# the compared framework too, which is the point: it is the only file allowed
# to, and no other current document may link to it or name it.
PARITY_DOC = "docs/reference/swiftui-parity.md"

# Content exception 2: a short, clearly labelled comparison for readers who
# already know another framework, allowed only inside docs/guide/** and only
# between these markers. The cap keeps it an aside: a comparison long enough to
# read as the contract is the failure the exception exists to prevent.
COMPARISON_BEGIN = "<!-- comparison:begin -->"
COMPARISON_END = "<!-- comparison:end -->"
COMPARISON_MAX_LINES = 15

#[[ DATED RECORDS: not scanned for rule 2. An accepted ADR and a consumed wave
#   plan are the EVIDENCE of a decision. Their cited sources are why the
#   decision was made, so rewriting them to remove a name falsifies the record
#   rather than cleaning the product. The maintained, current-facing documents
#   inside those directories are carved back in below and ARE scanned. ]]
VENDOR_HISTORY = (
    ("docs/adr/",
     "accepted decision records are append-only; an ADR is superseded, never edited",
     "never"),
    ("docs/plans/",
     "consumed wave plans record what a finished wave decided and measured",
     "Step 14 private-archive move"),
    ("docs/research/",
     "dated research records are raw findings, quoted and cited as read on the day",
     "Step 14 private-archive move"),
    ("vendor/",
     "third-party sources this repository does not author",
     "never"),
    ("build/",
     "generated distribution output; its inputs are scanned instead",
     "never"),
)

# ...and the documents inside those directories that ARE maintained,
# current-facing product surface. A reader is sent to each of these by a
# shipped document, so each must read in Facet and Roblox terms.
VENDOR_HISTORY_MAINTAINED = (
    "docs/plans/release-candidate-review.md",
    "docs/plans/agent-execution-contract.md",
    "docs/plans/facet-consolidated-roadmap.md",
    "docs/research/2026-08-12-haptics-engine-facts.md",
)

# (path-prefix-or-exact, pattern-that-may-match, reason, removal rule) — same
# shape as ALLOWLIST, applied only to the vendor profile.
VENDOR_ALLOWLIST = [
    (PARITY_DOC, VENDOR,
     "content exception 1: the one dedicated comparison document, path and body",
     "never (it IS the exception)"),
    ("tools/check_brand_drift.py", VENDOR,
     "the guard's own match data and its planted selftest words",
     "never (it IS the guard)"),
    #[[ FROZEN EVIDENCE, QUOTED BY PATH. artifacts/ is never scanned because a
    #   gate record keeps the name it was earned under. The gate manifest and a
    #   few specs QUOTE those paths, and a quoted path cannot be renamed
    #   without orphaning the evidence it points at. The pattern is the path
    #   itself, so a vendor word anywhere else in the same file is still
    #   caught. ]]
    ("*", re.compile(r"artifacts/[A-Za-z0-9._/-]*(?:swiftui|apple|ios|macos)", re.I),
     "a line quoting a path under artifacts/ quotes frozen gate evidence by its real name",
     "Step 14 gate/evidence archive"),
    #[[ GATE IDS ARE KEYS OF FROZEN EVIDENCE DIRECTORIES. Four earned gates are
    #   named for the stage that earned them, and each id is also the directory
    #   name under artifacts/ that holds its record. Renaming an id orphans the
    #   evidence every row of that gate proves, and artifacts/ is never
    #   rewritten. The registries that hold those ids are listed one by one so
    #   the exemption cannot spread. ]]
    #[[ THE GATE MANIFEST RUNS SHELL. Several rows grep the comparison document
    #   by its real path, because that is the file the command has to open. A
    #   command is not a document, and the pattern below excuses only the path
    #   itself, so vendor PROSE anywhere in a note is still caught. ]]
    ("tools/lune/gate_manifest.luau",
     re.compile(r"docs/reference/swiftui-parity\.md"),
     "run/evidence strings open the comparison document by the path it really has",
     "when the comparison document retires"),
    ("tools/lune/gate_manifest.luau", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    ("phases.json", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    ("requirements.json", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    ("docs/INVENTORY.md", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    ("tools/prior_gates.sh", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    ("docs/plans/facet-consolidated-roadmap.md", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    #[[ THE MACHINERY OF CONTENT EXCEPTION 1. The comparison document has a
    #   citation gate and a spec for that gate, and neither can do its job
    #   without holding the document's path, the vendor's documentation host,
    #   and the exact words the document uses. Same class of fact as this
    #   guard's own match list: the pattern below excuses a vendor word only
    #   when it sits INSIDE a Luau string literal, so an ordinary comment in
    #   either file is still caught. ]]
    ("tools/lune/check_docs.luau",
     re.compile(r"""["`'][^"`']*(?:swiftui|apple|ios)[^"`']*["`']""", re.I),
     "the comparison document's citation gate holds that document's path, citation host and fixed wording "
     "as literal match data",
     "when the comparison document retires"),
    ("tests/theme_docs.spec.luau",
     re.compile(r"""["`'][^"`']*(?:swiftui|apple|ios)[^"`']*["`']""", re.I),
     "the citation gate's own spec: its fixtures must be shaped like the document the gate reads",
     "same"),
    #[[ THE HOST CAPTURE HELPER. Two files of a compiled host language, used by
    #   the maintainer's screenshot tool. The language is not a Facet feature,
    #   a Facet concept, or a reason for anything Facet does — it is what the
    #   host compiler accepts, the same class of fact as a shell shebang. ]]
    ("tools/studio/capture_viewport.sh",
     re.compile(r"\bswift\b"),
     "the driver shell script invokes the host compiler by name",
     "when the capture helper stops needing a compiled host binary"),
    ("tools/studio/capture/", VENDOR,
     "the developer-only screen-capture helper is compiled by the host toolchain, which fixes "
     "its language and its file extension",
     "when the capture helper stops needing a compiled host binary"),
    #[[ ROBLOX'S OWN DEVICE-SUPPORT WORDS. The haptics research file records
    #   which devices the ENGINE says can vibrate, quoted verbatim from
    #   Roblox's documentation. The device list IS the platform fact the
    #   document exists to hold; paraphrasing it would make the quotation
    #   false. Only the device/OS half of the profile is excused here, so a
    #   framework or vendor name in that file is still caught. ]]
    ("docs/research/2026-08-12-haptics-engine-facts.md",
     re.compile(r"\bios\b|\biphone\b|\bmac\s?os\b|\bmac\b|\bipad\b", re.I),
     "verbatim quotations of Roblox's own haptics device-support matrix",
     "when Roblox restates that matrix without naming those devices"),
    #[[ THE ENGINE'S OWN DEVICE CATALOG. Roblox Studio's device emulator ships a
    #   catalog of real hardware profiles, and two kinds of test hold those
    #   names: a recorded snapshot of that catalog (the five-view selection
    #   policy is tested by being SHOWN one, which is the only way to prove it
    #   hard-codes nothing), and negative checks that assert a document names no
    #   device at all. Both are the engine's data, not Facet's words, and
    #   rewriting them would falsify the record or gut the check. ]]
    ("tests/matrix_rows.spec.luau", VENDOR,
     "a recorded snapshot of Roblox Studio's device-emulator catalog, plus the negative check that "
     "the selection policy hard-codes none of its ids",
     "when the catalog snapshot is re-read from Studio"),
    ("tools/lune/gate_manifest.luau",
     re.compile(r"iphone\|ipad\|android"),
     "a device-name prohibition list inside a gate command: the row asserts a module names no device",
     "never (it IS a check of this same rule)"),
    ("tests/callout.spec.luau",
     re.compile(r'"(?:iphone|ipad|macos)"'),
     "a device-name prohibition list: the check asserts the documentation names no device",
     "never (it IS a check of this same rule)"),
    ("tests/help.spec.luau",
     re.compile(r'"(?:iphone|ipad|macos)"'),
     "the same device-name prohibition list", "never"),
    ("src/controls/picker.luau",
     re.compile(r'"(?:iphone|ipad|macos)"'),
     "the same device-name prohibition list, asserted against this control's own source",
     "never"),
    #[[ HELD BY THE CONCURRENT EXTRACTION WORK (wave T12 scope note). These five
    #   modules are locked while their source-cap extraction lands; editing
    #   their comments here would collide with it. They are the ONLY unswept
    #   product source left, and the debt is named rather than hidden. ]]
    ("src/controls/table.luau", VENDOR,
     "extraction-locked: comments sweep with the extraction that owns this file",
     "when the table extraction lands"),
    ("src/layout/solver.luau", VENDOR,
     "extraction-locked: same rule", "when the solver extraction lands"),
    ("src/render/renderer.luau", VENDOR,
     "extraction-locked: same rule", "when the renderer extraction lands"),
    ("src/present/presenter.luau", VENDOR,
     "extraction-locked: same rule", "when the presenter extraction lands"),
    ("src/controls/virtual_list.luau", VENDOR,
     "extraction-locked: same rule", "when the virtual-list extraction lands"),
]

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
    ("docs/adr/ADR-0040-unreleased-breaking-changes.md", BRAND,
     "the unreleased-breaking-change ledger names the rename it records (row B-13)",
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


def matches(scope_path, entry_path):
    """Does an allowlist entry's path cover this file? `*` covers every file."""
    if entry_path == "*":
        return True
    return scope_path == entry_path or scope_path.startswith(entry_path.rstrip("/") + "/")


def allow(scope_path, line_text, pattern, allowlist):
    for path, pat, _reason, _removal in allowlist:
        if matches(scope_path, path):
            # An entry excuses a line when the entry's OWN pattern matches that
            # line — so a narrow entry (a frozen capture-schema string, a cited
            # spec filename) keeps its scope whichever profile pattern fired.
            # The BRAND shortcut is deliberately not extended to the tag half:
            # "this file may name the old product" is not "this file may keep a
            # `luau-*` theme tag".
            if pat.search(line_text) or (pat is BRAND and pattern is BRAND):
                return True
    return False


def vendor_history_skips(scope_path):
    """A dated record, and not one of the maintained documents inside one."""
    if scope_path in VENDOR_HISTORY_MAINTAINED:
        return False
    return any(scope_path.startswith(prefix) for prefix, _reason, _removal in VENDOR_HISTORY)


def scan_file(abs_path, scope_path, hits, profile=BRAND_PROFILE, allowlist=ALLOWLIST):
    base = os.path.basename(abs_path)
    allowed_path = any(matches(scope_path, p) for p, *_ in allowlist)
    for pattern in profile:
        if pattern.search(base) and not allowed_path:
            hits.append(f"{scope_path}: PATH carries a prohibited name")
            break
    #[[ THE MARKED COMPARISON BLOCK (content exception 2). Only inside
    #   docs/guide/**, only for the vendor profile, only between the two
    #   markers, and only for COMPARISON_MAX_LINES lines. An unbalanced marker,
    #   a marker outside docs/guide, and an over-long block each FAIL: an
    #   exception that cannot be seen ending is not an exception. ]]
    comparison = profile is VENDOR_PROFILE and scope_path.startswith("docs/guide/")
    inside = False
    block_start = 0
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                if comparison and (COMPARISON_BEGIN in line or COMPARISON_END in line):
                    # A marker outside docs/guide/ is not a marker at all: the
                    # exception does not reach there, so the words it tries to
                    # excuse are scanned normally.
                    if COMPARISON_BEGIN in line:
                        if inside:
                            hits.append(f"{scope_path}:{n}: comparison block opened twice")
                        inside, block_start = True, n
                    else:
                        if not inside:
                            hits.append(f"{scope_path}:{n}: comparison block closed but never opened")
                        inside = False
                    continue
                if inside:
                    if n - block_start > COMPARISON_MAX_LINES:
                        hits.append(f"{scope_path}:{n}: comparison block longer than "
                                    f"{COMPARISON_MAX_LINES} lines")
                        inside = False
                    else:
                        continue
                for pattern in profile:
                    if pattern.search(line) and not allow(scope_path, line, pattern, allowlist):
                        hits.append(f"{scope_path}:{n}: {line.strip()[:120]}")
                        break
        if inside:
            hits.append(f"{scope_path}:{block_start}: comparison block never closed")
    except OSError:
        pass


BINARY_SUFFIXES = (".rbxl", ".rbxm", ".png", ".jpg", ".gprx", ".pyc",
                   ".ttf", ".otf", ".webp", ".mov")


def scan_repo(repo, prefix, exclude, hits, profile=BRAND_PROFILE, allowlist=ALLOWLIST):
    for rel in tracked(repo):
        p = rel.replace("\\", "/")
        if any(p.startswith(t) or f"/{t}" in p for t in exclude):
            continue
        if prefix == "rr:" and any(p.startswith(t) for t in RR_DOC_HISTORY):
            continue
        if profile is VENDOR_PROFILE and vendor_history_skips(p):
            continue
        if p.endswith(BINARY_SUFFIXES):
            continue  # binaries are proved through the built-XML scan instead
        scan_file(os.path.join(repo, rel), prefix + p if prefix else p, hits,
                  profile, allowlist)


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
                            p.search(line) for p in BRAND_PROFILE + VENDOR_PROFILE):
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
    # rule 2 scans the framework repo only (see the module docstring)
    scan_repo(REPO, "", EXCLUDED_TREES, hits, VENDOR_PROFILE, VENDOR_ALLOWLIST)
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
    if selftest_vendor() != 0:
        return 1
    clean = run_scan(skip_builds=True)
    if clean:
        print("check_brand_drift: SELFTEST FAIL — restored tree not clean:")
        print("\n".join(clean[:20]))
        return 1
    print("check_brand_drift: SELFTEST PASS — rule 1: planted content, planted "
          "path, planted `luau-*` theme tag and an out-of-scope allowlist "
          "pattern each caught, `luau-analyze`/`luau-lsp` deliberately not; "
          "rule 2: a planted vendor word in src/ and one in docs/guide outside "
          "a marked block each caught, the same word inside a marked block "
          "deliberately not, an over-long and an unclosed block each caught; "
          "restored tree clean")
    return 0


def selftest_vendor():
    """Rule 2's negative control: prove the vendor profile and its one guide
    exception both behave. A guard nobody has watched fail proves nothing, and
    an exception nobody has watched WORK is an exception that silently is not
    there."""
    src_probe = os.path.join(REPO, "src", "vendor_probe_tmp.luau")
    guide_probe = os.path.join(REPO, "docs", "guide", "vendor_probe_tmp.md")
    marked_probe = os.path.join(REPO, "docs", "guide", "marked_probe_tmp.md")
    long_probe = os.path.join(REPO, "docs", "guide", "long_probe_tmp.md")
    open_probe = os.path.join(REPO, "docs", "guide", "open_probe_tmp.md")
    probes = (src_probe, guide_probe, marked_probe, long_probe, open_probe)
    try:
        with open(src_probe, "w") as f:
            f.write("-- planted: this reads like SwiftUI on iOS and must be caught\n")
        with open(guide_probe, "w") as f:
            f.write("Facet's stacks behave the way SwiftUI's do on iPadOS.\n")
        with open(marked_probe, "w") as f:
            f.write(f"# Guide\n\n{COMPARISON_BEGIN}\n"
                    "If you know SwiftUI: `UI.VStack` is its `VStack`. Optional.\n"
                    f"{COMPARISON_END}\n")
        with open(long_probe, "w") as f:
            body = "\n".join(f"line {i} about SwiftUI" for i in range(COMPARISON_MAX_LINES + 4))
            f.write(f"# Guide\n\n{COMPARISON_BEGIN}\n{body}\n{COMPARISON_END}\n")
        with open(open_probe, "w") as f:
            f.write(f"# Guide\n\n{COMPARISON_BEGIN}\nnever closed\n")

        def scan(path, scope):
            found = []
            scan_file(path, scope, found, VENDOR_PROFILE, VENDOR_ALLOWLIST)
            return found

        caught_src = scan(src_probe, "src/vendor_probe_tmp.luau")
        caught_guide = scan(guide_probe, "docs/guide/vendor_probe_tmp.md")
        inside_block = scan(marked_probe, "docs/guide/marked_probe_tmp.md")
        over_long = scan(long_probe, "docs/guide/long_probe_tmp.md")
        never_closed = scan(open_probe, "docs/guide/open_probe_tmp.md")
        failures = []
        if not caught_src:
            failures.append("a vendor word planted in src/ survived")
        if not caught_guide:
            failures.append("a vendor word planted in docs/guide outside a marked block survived")
        if inside_block:
            failures.append(f"the marked comparison block did not excuse its own text: {inside_block}")
        if not any("longer than" in h for h in over_long):
            failures.append("an over-long comparison block was not reported")
        if not any("never closed" in h for h in never_closed):
            failures.append("an unclosed comparison block was not reported")
        if failures:
            print("check_brand_drift: SELFTEST FAIL (rule 2) — " + "; ".join(failures))
            return 1
    finally:
        for path in probes:
            if os.path.exists(path):
                os.unlink(path)
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
