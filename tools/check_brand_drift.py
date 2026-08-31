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

  1. a short comparison block inside docs/guide/**, delimited by the markers
     `<!-- comparison:begin -->` / `<!-- comparison:end -->`, capped at
     COMPARISON_MAX_LINES so it stays an aside rather than a contract;
  2. the one public guide chapter that compares Facet with the other Roblox
     user-interface libraries a creator is choosing between, named file by file
     in VENDOR_ALLOWLIST.

A third exception used to exist — one dedicated comparison document under
docs/reference/. It was product research rather than product documentation, and
it was archived out of this repository on 2026-08-30
(docs/plans/distribution-readiness.md, "Private research and public framework
choice"). Its allowlist entry is gone with it, so this guard now refuses that
path like any other.

Dated records are not scanned for rule 2 (VENDOR_HISTORY): consumed wave plans
are the evidence of a decision, and rewriting one falsifies
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
# and appear in a dozen records. The four excluded stems are the Luau toolchain
# and two written-up traps about Luau syntax — not the retired brand, and legitimate
# in any file, which is why they are excluded structurally instead of by path:
#   lsp                              the Luau language server
#   analyze                          the Luau analyser binary
#   execution-session                a Roblox Open Cloud API scope name
#   interpolated-strings-single-line a Luau string-syntax trap, written up
#   require-by-string-init-self      a Luau require trap, written up
TAG = re.compile(r"\bluau-(?!lsp\b|analyze\b|execution-session\b"
                 r"|interpolated-strings-single-line"
                 r"|require-by-string-init-self)")

# every pattern the old-brand profile matches, in report order
#[[ A RENAME STATEMENT: the retired name, an arrow, the current name. Narrow on
#   purpose — it excuses a sentence that RECORDS the rename, never a file that
#   merely mentions the old brand (SCREEN-X, 2026-08-22). ]]
RENAME_ARROW = re.compile(
    r"[`\"]?(?:luau-\*?|LuauUI(?:_<id>)?)[`\"]?\s*->\s*[`\"]?(?:facet-|Facet)",
    re.IGNORECASE,
)

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

#[[ THE OTHER FRAMEWORK'S TYPE NAMES. `VENDOR` matches the vendor, its
#   operating systems, its sample applications and its domains. It matches no
#   TYPE names, and a reference page that explains a Facet property by naming
#   another framework's type is the prohibition verbatim — so these are matched
#   too.
#
#   CASE-SENSITIVE, and that is load-bearing. `UI.sensoryFeedback` and
#   `Controls.ProgressView` are Facet's own exports; the plan says not to rename
#   a stable Facet API because another framework uses the same generic name, so
#   `ViewThatFits` and `ProgressView` are deliberately absent. So is
#   `SensoryFeedback`: Facet spells its own `UI.sensoryFeedback` that way in
#   mounted-node ids, so the type name and a Facet identifier collide outright.
#
#   Every name below was checked against `lune run tools/lune/_probe_public_surface`
#   on 2026-08-21: none of them is a Facet export. A name that later BECOMES one
#   must come off this list rather than be worked around. ]]
VENDOR_TYPES = re.compile(
    r"\b(?:LazyVGrid|LazyHGrid|matchedGeometryEffect|EditButton|EditMode"
    r"|TableColumn|TableColumnAlignment|TimelineView|PhaseAnimator"
    r"|KeyPathComparator|swipeActions|symbolRenderingMode|foregroundStyle"
    r"|accessoryCircularCapacity|popoverTip|TipKit|UITableViewCell|NSTableView"
    r"|NSPopUpButton|NSTextField|UITextField|UIToolTipInteraction)\b"
    r"|\.contextMenu\b"
)

VENDOR_PROFILE = (VENDOR, VENDOR_TYPES)

# The earned gate ids that carry a retired stage name. Each is also a directory
# under artifacts/, which is frozen evidence and never rewritten.
#
# MATCHED BY SHAPE, NOT BY THE RETIRED NAME (2026-08-30). This used to spell the
# stage names out, which put the retired brand back into the guard's own source
# — the thing rule 2 exists to keep out of every other file. The shape is what
# the exception is actually about: a stage id ending in `-parity-round<n>` or
# `-reference-app-validation`, whatever prefix earned it. A rename of the stage
# therefore needs no edit here, and no vendor name lives in this file for it.
GATE_IDS = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*-parity-round\d"
                      r"|[a-z0-9]+(?:-[a-z0-9]+)*-reference-app-validation")

# Content exception 1: a short, clearly labelled comparison for readers who
# already know another framework, allowed only inside docs/guide/** and only
# between these markers. The cap keeps it an aside: a comparison long enough to
# read as the contract is the failure the exception exists to prevent.
COMPARISON_BEGIN = "<!-- comparison:begin -->"
COMPARISON_END = "<!-- comparison:end -->"
COMPARISON_MAX_LINES = 15

#[[ DATED RECORDS: not scanned for rule 2. A consumed wave plan is the EVIDENCE
#   of a decision. Its cited sources are why the decision was made, so rewriting
#   them to remove a name falsifies the record rather than cleaning the product.
#   The maintained, current-facing documents inside those directories are carved
#   back in below and ARE scanned. ]]
VENDOR_HISTORY = (
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
# shipped document, so each must read in Facet and Roblox terms. This list is
# the floor: REACHABILITY (below) carves back in anything a shipped page links.
VENDOR_HISTORY_MAINTAINED = (
    "docs/plans/release-candidate-review.md",
    "docs/plans/agent-execution-contract.md",
    "docs/plans/facet-consolidated-roadmap.md",
    "docs/research/2026-08-12-haptics-engine-facts.md",
)

#[[ ---- SCOPE BY REACHABILITY, NOT BY DIRECTORY -----------------------------
#   A directory is a filing decision; what the rule is about is whether a
#   READER is sent somewhere. A dated record nobody links is an archive. A
#   dated record a shipped page links is that page's continuation, and the rule
#   applies to it however it is filed, because "history" is not a licence for a
#   linked document to teach a Facet concept in another vendor's terms.
#
#   THE SHIPPED SURFACE is the set of documents a Roblox developer is told to
#   read. Anything it links, by markdown link or by written path, is IN SCOPE at
#   depth REACHABLE_DEPTH.
#
#   DEPTH IS 1, and that is a decision rather than a limitation. One click from
#   a shipped page is still that page recommending a document. Several clicks
#   through a roadmap hub reaches every plan the project has ever written,
#   which is the archive the exclusion exists for. The measured size of the
#   wider set is recorded in the wave's evidence file so the number is known
#   rather than assumed.
#
#   The comparison document is a LEAF: it is content exception 1, and following
#   its outbound links would drag its own sources into the shipped surface. ]]
SHIPPED_SURFACE = (
    "docs/guide/",
    "docs/extending/",
    "docs/reference/api.md",
    "docs/reference/constitution.md",
)
REACHABLE_DEPTH = 1

_MD_LINK = re.compile(r"\]\(([^)\s#]+)")
_WRITTEN_PATH = re.compile(r"(?:\.\./|docs/)[A-Za-z0-9_./-]+\.md")
_reachable_cache = None


def _references(rel):
    """Every document this one sends a reader to, however it spells the link."""
    try:
        with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return set()
    out = set()
    here = os.path.dirname(rel)
    for match in _MD_LINK.finditer(text):
        target = match.group(1)
        if not target.startswith(("http", "mailto:")):
            out.add(os.path.normpath(os.path.join(here, target)))
    for match in _WRITTEN_PATH.finditer(text):
        target = match.group(0)
        out.add(os.path.normpath(os.path.join(here, target) if target.startswith("../") else target))
    return {p.replace("\\", "/") for p in out}


def reachable_documents():
    """The documents the shipped surface sends a reader to, cached."""
    global _reachable_cache
    if _reachable_cache is not None:
        return _reachable_cache
    # walked from disk, not from git: a shipped chapter that is not committed
    # yet is still a page a reader is sent to, and the selftest depends on it
    frontier = []
    for entry in SHIPPED_SURFACE:
        root = os.path.join(REPO, entry)
        if os.path.isfile(root):
            frontier.append(entry)
            continue
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if name.endswith(".md"):
                frontier.append(entry.rstrip("/") + "/" + name)
    seen = set(frontier)
    for _ in range(REACHABLE_DEPTH):
        nxt = []
        for rel in frontier:
            for target in _references(rel):
                if not target.endswith(".md") or target.startswith("artifacts/"):
                    continue
                if not os.path.isfile(os.path.join(REPO, target)):
                    continue
                if target not in seen:
                    seen.add(target)
                    nxt.append(target)
        frontier = nxt
    _reachable_cache = seen
    return seen

# (path-prefix-or-exact, pattern-that-may-match, reason, removal rule) — same
# shape as ALLOWLIST, applied only to the vendor profile.
VENDOR_ALLOWLIST = [
    ("tools/check_brand_drift.py", VENDOR,
     "the guard's own match data and its planted selftest words",
     "never (it IS the guard)"),
    #[[ CONTENT EXCEPTION 3: THE PUBLIC LIBRARY-CHOICE GUIDE. One chapter of the
    #   guide exists to help a Roblox creator choose between Facet and the other
    #   Roblox user-interface libraries, and the release plan asks for it by
    #   name. It is a comparison from end to end, so the marked-block exception
    #   above cannot hold it: that one caps an aside at COMPARISON_MAX_LINES
    #   lines, and a whole chapter is not an aside.
    #
    #   The entry names ONE FILE and no prefix, so the exception cannot spread to
    #   a sibling chapter, and every other guide page is still scanned exactly as
    #   before. Rule 2 is unchanged for the rest of the tree: Facet still explains
    #   ITSELF in Roblox and Facet terms, and this page explains a CHOICE, which
    #   is the one job that cannot be done without naming what is being chosen
    #   between. ]]
    ("docs/guide/14-choosing-a-ui-library.md", VENDOR,
     "content exception 3: the one public guide chapter that compares Facet with "
     "the other Roblox user-interface libraries a creator is choosing between; a "
     "comparison may name what it compares, and it is longer than the marked-block "
     "exception allows",
     "when the library-choice chapter retires"),
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
    #[[ REMOVED 2026-08-30: the entry that excused gate-manifest run strings for
    #   opening the dedicated comparison document by its real path. Its own
    #   removal rule was "when the comparison document retires", and it has —
    #   the document was archived out of this repository and the tracked copy
    #   deleted. Any run string still naming that path is opening a file that no
    #   longer exists, so it is a broken gate row and not an exception to grant.
    #   The gate rows that did so are listed for their owner in
    #   artifacts/distribution-readiness/swiftui-migration.md. ]]
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
    ("docs/MAINTAINERS.md", GATE_IDS,
     "the maintainer map's `gates` column cites earned gate ids by their real names, "
     "the same reason INVENTORY.md and prior_gates.sh carry this entry",
     "Step 14 gate/evidence archive"),
    ("tools/prior_gates.sh", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    ("docs/plans/facet-consolidated-roadmap.md", GATE_IDS,
     "an earned gate id, which is also the name of its frozen artifacts/ directory",
     "Step 14 gate/evidence archive"),
    #[[ REMOVED 2026-08-30, same removal rule and same trigger. The citation
    #   gate in tools/lune/check_docs.luau and its spec in
    #   tests/theme_docs.spec.luau used to hold the retired document's path, its
    #   vendor documentation host and its fixed wording as literal match data.
    #   The gate now reads whatever comparison document the public tree carries,
    #   asks for an https:// URL rather than one particular host, and its
    #   fixtures name only Roblox libraries — so neither file contains a vendor
    #   word any more and neither needs an exception. ]]
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
    #[[ SCOPED TO THE QUOTATION, NOT TO THE FILE (re-review §2). The first
    #   version of this entry was file-scoped, so its stated reason — "verbatim
    #   quotations" — also excused four lines of the author's OWN prose about
    #   the machine the probe ran on. Those four are rewritten; the pattern now
    #   requires the device name to sit inside quotation marks, which is what a
    #   quotation is. ]]
    ("docs/research/2026-08-12-haptics-engine-facts.md",
     re.compile(r"(?:[\"\u201c\u201d][^\"\u201c\u201d]*|^>\s)"
                r".*?(?:\bios\b|\biphone\b|\bmac\s?os\b|\bmac\b|\bipad\b)",
                re.I),
     "verbatim quotations of Roblox's own haptics device-support matrix; the device name has "
     "to be inside the quotation marks, or on a blockquote line, which is how a quotation "
     "that wraps is written in markdown",
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
    #[[ `src/controls/virtual_list.luau` LEFT THIS LIST on 2026-08-22, the round its
    #   hosted half became `controls/virtual_list_hosted.luau`. Its entry read
    #   "when the virtual-list extraction lands", and it landed — so the sweep it
    #   was deferring came due. Six sites were reworded rather than re-exempted,
    #   and the NEW module was never added here: an extraction inherits none of its
    #   host's exemptions (the same rule `tools/lune/verify/data/source-cap-ledger.md`'s head
    #   states for `check_comment_codes`, and the same way it bites — the four
    #   comments that rode out of the locked file were live the moment the split
    #   commit landed). Adding the sibling would have re-created the debt under a
    #   new name. ]]
    ("src/layout/solver.luau", VENDOR,
     "extraction-locked: same rule", "when the solver extraction lands"),
    ("src/present/presenter.luau", VENDOR,
     "extraction-locked: same rule", "when the presenter extraction lands"),
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
    #[[ THE DECODER OF FROZEN EVIDENCE (wave T15). Every MicroProfiler dump this
    #   project has ever taken predates the rename and literally CONTAINS the
    #   string `LuauUI/arrange`; a capture is immutable evidence and its scope
    #   names are part of what it recorded. A decoder that may not name them
    #   cannot read them — which is not hypothetical: with a hard-coded `Facet/`
    #   filter this tool printed an empty table for the whole corpus, and an empty
    #   table reads as "the framework did no work". Scoped to the one PREFIX
    #   string rather than to BRAND across the file, so an ordinary old-brand
    #   mention here is still caught. ]]
    ("tools/microprofiler_aggregate.py", re.compile(r"LuauUI/"),
     "the pre-rename scope prefix is DATA about stored captures, not a name this "
     "tool wears; both prefixes are decoded and the legacy one is announced",
     "when no capture predating the rename is still cited as evidence — i.e. after "
     "the device rows are re-taken on a Facet-named place"),
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
     "the naming-adr-implemented note states WHICH tag family the rename retired; a gate note "
     "that cannot name the old vocabulary cannot record that it moved",
     "permanent (the note is the gate's own history)"),
    ("tools/lune/gate_manifest.luau",
     re.compile(r"BRAND is luau\[\\\\s\._-\]\?ui and there is no ui after luau in a tag"),
     "the same note quotes this checker's own BRAND pattern to explain why 346 surviving "
     "tags were structurally invisible to it",
     "permanent (same reason)"),
    #[[ THE RENAME ARROW (SCREEN-X, 2026-08-22). The two renames left three
    #   prefix tests comparing the wrong number of characters — `luau-` is five
    #   where `facet-` is six, and `LuauUI` is six where `Facet` is five — and the
    #   worst of them made the adapter's tag-REMOVAL loop dead code for four days.
    #   The fix, the module it lives in, its spec and its registration all have to
    #   say WHICH rename did it and in WHICH direction, and a comment that may not
    #   name the retired vocabulary cannot record that it moved: that is the same
    #   judgement the gate_manifest entry above already makes.
    #
    #   SCOPED TO THE ARROW, NOT TO THE FILE (the R5 review §2-1 lesson, which
    #   these two would otherwise repeat): the patterns match only a rename
    #   statement — the retired name, an arrow, the current name — so an ordinary
    #   old-brand mention anywhere else in any of these four files is still caught.
    #   Proved by planting one and watching the checker fail. ]]
    ("src/render/tag_sync.luau", RENAME_ARROW,
     "the ruling's header names the rename that broke it, in the direction it went",
     "when the rename is old enough that the defect needs no explanation — i.e. never, "
     "while the module's job is to make that defect unrepeatable"),
    ("tests/prefix_tests.spec.luau", RENAME_ARROW,
     "the scanner's header states the defect class it exists for, with both renames",
     "same"),
    ("tests/run.luau", RENAME_ARROW,
     "the spec's registration blurb says what it guards and why there were three",
     "same"),
    ("tools/studio/device_matrix.luau", RENAME_ARROW,
     "the root filter's comment records that its six-character test outlived the "
     "five-character literal the rename gave it",
     "same"),
    ("docs/handoff/SCREEN-X-OWED-LIVE-WORK.md", RENAME_ARROW,
     "the owed-work register has to say which rename broke what, in both directions",
     "when all four owed items are closed and the register is archived"),
    ("docs/handoff/SCREEN-X-OWED-LIVE-WORK.md",
     re.compile(r"pl9-row3-luauui-1\.json"),
     "cites the PRE-RENAME capture by its real filename as the control to compare a "
     "re-capture against; a citation that renames its source cannot be followed",
     "when that capture is superseded by a Facet-named re-capture"),
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
            # An entry written against VENDOR excuses the whole vendor profile:
            # "this file may carry the other framework's language" is one fact,
            # and its type names are that language too.
            if pat.search(line_text) \
               or (pat is BRAND and pattern is BRAND) \
               or (pat is VENDOR and pattern is VENDOR_TYPES):
                return True
    return False


def vendor_history_skips(scope_path):
    """A dated record nobody sends a reader to.

    Three ways to stay in scope: the path is not a dated record at all; it is
    named in VENDOR_HISTORY_MAINTAINED; or a shipped document links it.
    """
    if scope_path in VENDOR_HISTORY_MAINTAINED:
        return False
    if not any(scope_path.startswith(prefix) for prefix, _reason, _removal in VENDOR_HISTORY):
        return False
    return scope_path not in reachable_documents()


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
          "deliberately not, an over-long and an unclosed block each caught, "
          "and an unlinked dated record went IN scope the moment a shipped page "
          "linked it; restored tree clean")
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
    made_dirs: list = []
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

        #[[ THE REACHABILITY ARM. A dated record nobody links is out of scope; the
        #   same file becomes IN scope the moment a shipped page links it, and
        #   nothing about the file itself changes. Both halves are driven here,
        #   because a scope rule nobody has watched switch is a scope rule
        #   nobody knows the shape of. ]]
        global _reachable_cache
        _reachable_cache = None
        #[[ THE PROBE'S TREE IS ARCHIVED, SO THE SELFTEST MAKES ITS OWN.
        #   `docs/plans/` left the tip with the rest of the stage record, and the
        #   plant died on a missing directory before it could assert anything.
        #   The RULE is still declared in VENDOR_HISTORY and is still what this
        #   case exercises, so the probe keeps its path and the selftest creates
        #   the directory it needs and takes it away again — the tree is
        #   byte-identical afterwards, which the `finally` below now enforces for
        #   the directory as well as for the files. ]]
        unlinked = "docs/plans/reachability_probe_tmp.md"
        for probe_dir in (os.path.dirname(os.path.join(REPO, unlinked)),):
            if not os.path.isdir(probe_dir):
                os.makedirs(probe_dir)
                made_dirs.append(probe_dir)
        with open(os.path.join(REPO, unlinked), "w") as f:
            f.write("# probe\n\nThis reads like SwiftUI on iOS.\n")
        probes = probes + (os.path.join(REPO, unlinked),)
        before = vendor_history_skips(unlinked)
        guide = os.path.join(REPO, "docs", "guide", "reachability_probe_tmp.md")
        with open(guide, "w") as f:
            f.write(f"# probe\n\nSee [the plan](../plans/reachability_probe_tmp.md).\n")
        probes = probes + (guide,)
        _reachable_cache = None
        after = vendor_history_skips(unlinked)
        if not before or after:
            print("check_brand_drift: SELFTEST FAIL (rule 2) — reachability did not decide "
                  f"scope: unlinked skipped={before}, linked skipped={after}")
            return 1

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
        for probe_dir in reversed(made_dirs):
            try:
                os.rmdir(probe_dir)
            except OSError:
                pass
        _reachable_cache = None
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
