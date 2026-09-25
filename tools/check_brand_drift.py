#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STUDIO_ROOT = os.path.abspath(os.path.join(REPO, "..", "..", ".."))
RR = os.path.join(STUDIO_ROOT, "games", "RascalRally", "code")

BRAND = re.compile(r"luau[\s._-]?ui", re.IGNORECASE)

TAG = re.compile(r"\bluau-(?!lsp\b|analyze\b|execution-session\b"
                 r"|interpolated-strings-single-line"
                 r"|require-by-string-init-self)")

RENAME_ARROW = re.compile(
    r"[`\"]?(?:luau-\*?|LuauUI(?:_<id>)?)[`\"]?\s*->\s*[`\"]?(?:facet-|Facet)",
    re.IGNORECASE,
)

BRAND_PROFILE = (BRAND, TAG)

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

VENDOR_TYPES = re.compile(
    r"\b(?:LazyVGrid|LazyHGrid|matchedGeometryEffect|EditButton|EditMode"
    r"|TableColumnAlignment|TimelineView|PhaseAnimator"
    r"|KeyPathComparator|swipeActions|symbolRenderingMode|foregroundStyle"
    r"|accessoryCircularCapacity|popoverTip|TipKit|UITableViewCell|NSTableView"
    r"|NSPopUpButton|NSTextField|UITextField|UIToolTipInteraction)\b"
    r"|\.contextMenu\b"
)

VENDOR_PROFILE = (VENDOR, VENDOR_TYPES)

FACET_EXPORTS = "src/init.luau"

COMPARISON_BEGIN = "<!-- comparison:begin -->"
COMPARISON_END = "<!-- comparison:end -->"
COMPARISON_MAX_LINES = 15

VENDOR_HISTORY = (
    ("docs/plans/",
     "consumed plans record what a finished wave decided and measured",
     "private-archive move"),
    ("vendor/",
     "third-party sources this repository does not author",
     "never"),
    ("build/",
     "generated distribution output; its inputs are scanned instead",
     "never"),
)

VENDOR_HISTORY_MAINTAINED = (
    "docs/plans/README.md",
)

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
    global _reachable_cache
    if _reachable_cache is not None:
        return _reachable_cache
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


VENDOR_ALLOWLIST = [
    ("tests/native_parity_navigation.spec.luau", re.compile(r'"iphone", "ipad"'),
     "a negative test lists device names to prove no control branches on one",
     "when the device-name guard moves to a shared helper"),
    ("tests/native_parity_weaker_pointer.spec.luau", re.compile(r'"iphone", "ipad"'),
     "a negative test lists device names to prove no control branches on one",
     "when the device-name guard moves to a shared helper"),
    ("tools/check_brand_drift.py", VENDOR,
     "the guard's own match data and its planted selftest words",
     "never"),
    ("docs/guide/14-choosing-a-ui-library.md", VENDOR,
     "the one public guide chapter that compares Facet with the other Roblox user-interface "
     "libraries a creator is choosing between; it is longer than the marked-block exception allows",
     "when the library-choice chapter retires"),
    ("*", re.compile(r"artifacts/[A-Za-z0-9._/-]*(?:swiftui|apple|ios|macos)", re.I),
     "a line quoting a path under artifacts/ quotes frozen gate evidence by its real name",
     "gate evidence archive"),
    ("tools/studio/capture_viewport.sh", re.compile(r"\bswift\b"),
     "the driver shell script invokes the host compiler by name",
     "when the capture helper stops needing a compiled host binary"),
    ("tools/studio/capture/", VENDOR,
     "the developer-only screen-capture helper is compiled by the host toolchain, which fixes "
     "its language and its file extension",
     "when the capture helper stops needing a compiled host binary"),
    (".github/workflows/ci.yml", re.compile(r"(?:runs-on|- os):\s*macos-\d+\b"),
     "a hosted CI runner label is an infrastructure fact about where CI runs, not a feature name",
     "when CI stops using that runner image"),
    ("docs/guide/12-performance-lab.md", re.compile(r"`macos-\d+`\s+ARM runner"),
     "names the hosted CI runner image the timing gate runs on",
     "when the timing gate moves to another runner"),
    ("docs/guide/18-verification-scope.md", re.compile(r"CI lane moved to macOS ARM"),
     "records which hosted CI runner the verification lane runs on",
     "when the lane moves to another runner"),
    ("docs/guide/19-paired-performance.md",
     re.compile(r"CPU: `Apple M\d[\w ]*`|OS: macOS \d|Apple-silicon Mac\b|same Mac\b"),
     "describes the benchmark host a recorded measurement ran on; the hardware and OS are "
     "part of the measurement",
     "when the paired run is re-recorded on another host"),
    ("docs/guide/20-verification-parity.md", re.compile(r"`macos-\d+`"),
     "records the CI runner move as a verification-scope fact",
     "when the parity record is archived"),
    ("tools/lune/verification_parity.json", VENDOR,
     "the audit record of main's baseline quotes main's spec titles and gap text verbatim, "
     "including device-name prohibition checks; it is frozen evidence of that baseline",
     "when the parity audit is archived"),
]

EXCLUDED_TREES = (
    ("artifacts/", "gate evidence records the name it was earned under"),
    ("docs/superpowers/", "the frozen original design spec"),
    (".superpowers/", "controller scratch, git-ignored"),
)

RR_DOC_HISTORY = ("docs/missions/", "docs/playtests/", "docs/DECISIONS.md")

ALLOWLIST = [
    ("tools/microprofiler_aggregate.py", re.compile(r"LuauUI/"),
     "the pre-rename scope prefix is data about stored captures, not a name this tool wears",
     "when no capture predating the rename is still cited as evidence"),
    ("tools/check_perf_gate_evidence.py", BRAND,
     "reads frozen capture artifacts whose schema strings predate the rename",
     "when those capture schemas are re-recorded under Facet"),
    ("tools/check_perf_captures.py", BRAND,
     "same frozen-capture schema rule",
     "same"),
    ("tools/lune/verification_parity.json", BRAND,
     "the audit record of main's baseline quotes main's spec names, titles and gap text verbatim; "
     "it is frozen evidence of that baseline, and rewriting it would falsify the comparison",
     "when the parity audit is archived"),
    ("requirements.json", re.compile(r"2026-07-19-luauui-crossplatform", re.I),
     "cites the frozen design-spec file under docs/superpowers/ by its real name",
     "when that design spec is archived"),
    ("tools/check_brand_drift.py", BRAND,
     "the guard's own match data", "never"),
    ("tools/check_brand_drift.py", TAG,
     "the guard's own tag-pattern match data and its planted selftest tag", "never"),
    ("rr:src/client/FacetFlags.luau", BRAND,
     "dual-read fallback: the five pre-rename attribute names are the migration",
     "docs/migrations/facet-attribute-migration.md removal trigger"),
    ("rr:tests/facet_flag_migration.spec.luau", BRAND,
     "asserts the dual-read fallback by its real attribute names", "same"),
    ("rr:src/client/init.client.luau", BRAND,
     "one line routes readers to the migration doc", "same"),
    ("rr:tests/run.luau", BRAND,
     "one line explains the migration spec's fake workspace", "same"),
    ("rr:tests/facet_help_callout_contract.spec.luau", BRAND,
     "explains a pinned order that moved in the rename", "next re-pin"),
    ("rr:tests/facet_motion_and_scroll_contract.spec.luau", BRAND,
     "same rule", "next re-pin"),
    ("rr:tests/facet_theme_paint_contract.spec.luau", BRAND,
     "same rule", "next re-pin"),
    ("studio:games/RascalRally/docs/DECISIONS.md", BRAND,
     "append-only decision ledger; old entries keep the name they were written under",
     "never"),
    ("studio:games/RascalRally/docs/migrations/facet-attribute-migration.md", BRAND,
     "the migration manifest names the five attributes it migrates",
     "its own removal trigger"),
    ("studio:games/RascalRally/docs/FACET_SETTINGS_PORT.md",
     re.compile(r"2026-07-19-luauui-crossplatform", re.I),
     "frozen-spec citation", "archive"),
]

SKIPPED_TREES = []


def present(repo, label):
    if not os.path.isdir(repo):
        SKIPPED_TREES.append(label)
        return False
    out = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True)
    if out.returncode != 0:
        SKIPPED_TREES.append(label)
        return False
    return True


def listed(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(f"check_brand_drift: FAIL_ENVIRONMENT git ls-files in {repo}")
        sys.exit(2)
    return sorted(set(out.stdout.splitlines()))


def matches(scope_path, entry_path):
    if entry_path == "*":
        return True
    return scope_path == entry_path or scope_path.startswith(entry_path.rstrip("/") + "/")


def allow(scope_path, line_text, pattern, allowlist):
    for path, pat, _reason, _removal in allowlist:
        if matches(scope_path, path):
            if pat.search(line_text) \
               or (pat is BRAND and pattern is BRAND) \
               or (pat is VENDOR and pattern is VENDOR_TYPES):
                return True
    return False


def vendor_history_skips(scope_path):
    if scope_path in VENDOR_HISTORY_MAINTAINED:
        return False
    if not any(scope_path.startswith(prefix) for prefix, _reason, _removal in VENDOR_HISTORY):
        return False
    return scope_path not in reachable_documents()


def scan_file(abs_path, scope_path, hits, profile=BRAND_PROFILE, allowlist=ALLOWLIST):
    base = os.path.basename(abs_path)
    allowed_path = any(matches(scope_path, p) and p != "*" for p, *_ in allowlist)
    for pattern in profile:
        if pattern.search(base) and not allowed_path:
            hits.append(f"{scope_path}: PATH carries a prohibited name")
            break
    comparison = profile is VENDOR_PROFILE and scope_path.startswith("docs/guide/")
    inside = False
    block_start = 0
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                if comparison and (COMPARISON_BEGIN in line or COMPARISON_END in line):
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
    for rel in listed(repo):
        p = rel.replace("\\", "/")
        if any(p.startswith(t) or f"/{t}" in p for t in exclude):
            continue
        if prefix == "rr:" and any(p.startswith(t) for t in RR_DOC_HISTORY):
            continue
        if profile is VENDOR_PROFILE and vendor_history_skips(p):
            continue
        if p.endswith(BINARY_SUFFIXES):
            continue
        abs_path = os.path.join(repo, rel)
        if not os.path.isfile(abs_path):
            continue
        scan_file(abs_path, prefix + p if prefix else p, hits, profile, allowlist)


def facet_exports():
    with open(os.path.join(REPO, FACET_EXPORTS), encoding="utf-8") as fh:
        source = fh.read()
    return set(re.findall(r"^export type ([A-Za-z_]\w*)", source, re.M)) \
        | set(re.findall(r"^\t([A-Za-z_]\w*)\s*=", source, re.M))


def stale_entries():
    problems = []
    for name in sorted(facet_exports()):
        if VENDOR_TYPES.fullmatch(name):
            problems.append(f"VENDOR_TYPES matches `{name}`, which {FACET_EXPORTS} exports; "
                            "take it off the list")
    for label, allowlist in (("ALLOWLIST", ALLOWLIST), ("VENDOR_ALLOWLIST", VENDOR_ALLOWLIST)):
        for path, _pat, reason, _removal in allowlist:
            if not reason:
                problems.append(f"{label} entry {path} carries no reason")
            if path == "*" or path.startswith(("rr:", "studio:")):
                continue
            if not os.path.exists(os.path.join(REPO, path)):
                problems.append(f"{label} entry {path} names a path that no longer exists")
    for path in VENDOR_HISTORY_MAINTAINED:
        if not os.path.exists(os.path.join(REPO, path)):
            problems.append(f"VENDOR_HISTORY_MAINTAINED entry {path} names a path that no longer exists")
    return problems


def scan_builds(hits):
    projects = [p for p in listed(REPO) if p.endswith(".project.json")
                and not any(p.startswith(t) for t, _reason in EXCLUDED_TREES)]
    rojo = shutil.which("rojo") or os.path.expanduser("~/.rokit/bin/rojo")
    if not os.path.exists(rojo):
        print("check_brand_drift: FAIL_ENVIRONMENT rojo missing")
        sys.exit(2)
    for proj in projects:
        handle, tmp = tempfile.mkstemp(suffix=".rbxlx")
        os.close(handle)
        try:
            r = subprocess.run([rojo, "build", proj, "-o", tmp], cwd=REPO,
                               capture_output=True, text=True)
            if r.returncode != 0:
                hits.append(f"{proj}: rojo build failed: {r.stderr.strip()[:160]}")
                continue
            with open(tmp, encoding="utf-8", errors="replace") as fh:
                for n, line in enumerate(fh, 1):
                    if 'name="Name"' in line and any(
                            p.search(line) for p in BRAND_PROFILE + VENDOR_PROFILE):
                        hits.append(f"{proj} (built XML) line {n}: {line.strip()[:120]}")
        finally:
            os.unlink(tmp)


def studio_surfaces(hits):
    if not os.path.isdir(os.path.join(STUDIO_ROOT, "GameStudio", "specialists")):
        SKIPPED_TREES.append("the studio tree above this repository")
        return
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
            scan_file(f, "studio:" + os.path.relpath(f, STUDIO_ROOT), hits)


def run_scan(skip_builds=False):
    hits = []
    del SKIPPED_TREES[:]
    hits += stale_entries()
    excluded = tuple(t for t, _reason in EXCLUDED_TREES)
    scan_repo(REPO, "", excluded, hits)
    if present(RR, "the consuming game's checkout"):
        scan_repo(RR, "rr:", (), hits)
    studio_surfaces(hits)
    scan_repo(REPO, "", excluded, hits, VENDOR_PROFILE, VENDOR_ALLOWLIST)
    if skip_builds:
        SKIPPED_TREES.append("the built-place name scan (--skip-builds)")
    else:
        scan_builds(hits)
    return hits


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def selftest():
    global _reachable_cache
    created = []
    made_dirs = []
    failures = []

    def plant(rel, text):
        path = os.path.join(REPO, rel)
        directory = os.path.dirname(path)
        if not os.path.isdir(directory):
            os.makedirs(directory)
            made_dirs.append(directory)
        created.append(path)
        write(path, text)
        return path

    def scanned(rel, profile=BRAND_PROFILE, allowlist=ALLOWLIST):
        found = []
        scan_file(os.path.join(REPO, rel), rel, found, profile, allowlist)
        return found

    def vendor(rel):
        return scanned(rel, VENDOR_PROFILE, VENDOR_ALLOWLIST)

    try:
        plant("src/drift_probe_tmp.luau", "local planted = \"LuauUI must be caught here\"\nreturn planted\n")
        plant("tests/luauui_probe_tmp.luau", "return {}\n")
        plant("src/drift_probe_allow_tmp.luau", "local stamp = \"luauui-theme/1\"\nreturn stamp\n")
        plant("src/tag_probe_tmp.luau", "local tag = \"luau-chrome-panel\"\nreturn tag\n")
        plant("src/toolchain_probe_tmp.luau", "local tools = \"luau-analyze luau-lsp\"\nreturn tools\n")
        plant("docs/drift_parity_probe_tmp.json", "{\"note\":\"LuauUI outside the parity record\"}\n")
        if not scanned("src/drift_probe_tmp.luau"):
            failures.append("rule 1: planted old-brand content survived")
        if not any("PATH carries" in h for h in scanned("tests/luauui_probe_tmp.luau")):
            failures.append("rule 1: planted old-brand path survived")
        if not scanned("src/drift_probe_allow_tmp.luau"):
            failures.append("rule 1: an allowlisted pattern outside its path survived")
        if not scanned("src/tag_probe_tmp.luau"):
            failures.append("rule 1: planted luau-* theme tag survived")
        if scanned("src/toolchain_probe_tmp.luau"):
            failures.append("rule 1: a Luau toolchain name was reported as brand drift")
        if not scanned("docs/drift_parity_probe_tmp.json"):
            failures.append("rule 1: the parity-record exception reached another file")

        plant("src/vendor_probe_tmp.luau", "local planted = \"this reads like SwiftUI on iOS\"\nreturn planted\n")
        plant("docs/guide/vendor_probe_tmp.md", "Facet's stacks behave the way SwiftUI's do on iPadOS.\n")
        plant("docs/guide/marked_probe_tmp.md",
              f"# Guide\n\n{COMPARISON_BEGIN}\nIf you know SwiftUI: a list layout is its stack.\n"
              f"{COMPARISON_END}\n")
        body = "\n".join(f"line {i} about SwiftUI" for i in range(COMPARISON_MAX_LINES + 4))
        plant("docs/guide/long_probe_tmp.md", f"# Guide\n\n{COMPARISON_BEGIN}\n{body}\n{COMPARISON_END}\n")
        plant("docs/guide/open_probe_tmp.md", f"# Guide\n\n{COMPARISON_BEGIN}\nnever closed\n")
        plant("src/vendor_type_probe_tmp.luau", "local grid = \"LazyVGrid\"\nreturn grid\n")
        plant("src/runner_probe_tmp.yml", "runs-on: macos-15\n")
        plant("docs/guide/runner_probe_tmp.md", "Facet feels like a Mac app.\n")
        if not vendor("src/vendor_probe_tmp.luau"):
            failures.append("rule 2: a vendor word planted in src/ survived")
        if not vendor("docs/guide/vendor_probe_tmp.md"):
            failures.append("rule 2: a vendor word in docs/guide outside a marked block survived")
        inside = vendor("docs/guide/marked_probe_tmp.md")
        if inside:
            failures.append(f"rule 2: the marked comparison block did not excuse its own text: {inside}")
        if not any("longer than" in h for h in vendor("docs/guide/long_probe_tmp.md")):
            failures.append("rule 2: an over-long comparison block was not reported")
        if not any("never closed" in h for h in vendor("docs/guide/open_probe_tmp.md")):
            failures.append("rule 2: an unclosed comparison block was not reported")
        if not vendor("src/vendor_type_probe_tmp.luau"):
            failures.append("rule 2: another framework's type name survived")
        if not vendor("src/runner_probe_tmp.yml"):
            failures.append("rule 2: the CI runner exception reached another file")
        if not vendor("docs/guide/runner_probe_tmp.md"):
            failures.append("rule 2: a vendor word in a guide page outside the host-description lines survived")

        unlinked = "docs/plans/reachability_probe_tmp.md"
        plant(unlinked, "# probe\n\nThis reads like SwiftUI on iOS.\n")
        _reachable_cache = None
        before = vendor_history_skips(unlinked)
        plant("docs/guide/reachability_probe_tmp.md",
              "# probe\n\nSee [the plan](../plans/reachability_probe_tmp.md).\n")
        _reachable_cache = None
        after = vendor_history_skips(unlinked)
        if not before or after:
            failures.append(f"rule 2: reachability did not decide scope: unlinked skipped={before}, "
                            f"linked skipped={after}")

        ALLOWLIST.append(("src/deleted_probe_tmp.luau", BRAND, "probe", "probe"))
        try:
            if not any("deleted_probe_tmp" in p for p in stale_entries()):
                failures.append("an allowlist entry for a deleted file was not reported")
        finally:
            ALLOWLIST.pop()

        planted = run_scan(skip_builds=True)
        for rel in ("src/drift_probe_tmp.luau", "src/vendor_probe_tmp.luau",
                    "docs/guide/vendor_probe_tmp.md", "docs/plans/reachability_probe_tmp.md"):
            if not any(h.startswith(rel) for h in planted):
                failures.append(f"the full scan missed the planted file {rel}")
    finally:
        for path in created:
            if os.path.exists(path):
                os.unlink(path)
        for directory in reversed(made_dirs):
            try:
                os.rmdir(directory)
            except OSError:
                pass
        _reachable_cache = None
    if failures:
        print("check_brand_drift: SELFTEST FAIL")
        print("\n".join(failures))
        return 1
    clean = run_scan(skip_builds=True)
    if clean:
        print("check_brand_drift: SELFTEST FAIL - restored tree not clean:")
        print("\n".join(clean[:20]))
        return 1
    print("check_brand_drift: SELFTEST PASS - rule 1: planted content, path, luau-* tag, an "
          "out-of-scope allowlist pattern and an old-brand line outside the parity record each "
          "caught, luau-analyze and luau-lsp not; rule 2: planted vendor words in src/ and "
          "docs/guide, a vendor type name, a runner label outside ci.yml and a vendor word outside "
          "the host-description lines each caught, a marked block excused, over-long and unclosed "
          "blocks caught, and an unlinked dated record went in scope once a shipped page linked "
          "it; an allowlist entry for a deleted file reported; restored tree clean")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    hits = run_scan(skip_builds="--skip-builds" in sys.argv)
    if hits:
        print(f"check_brand_drift: FAIL - {len(hits)} match(es) outside the allowlist:")
        for h in hits[:60]:
            print("  " + h)
        if len(hits) > 60:
            print(f"  ... and {len(hits) - 60} more")
        sys.exit(1)
    print("check_brand_drift: PASS - no old-brand or vendor-language drift outside the recorded "
          "allowlist")
    for tree in SKIPPED_TREES:
        print(f"  NOT SCANNED: {tree}")


if __name__ == "__main__":
    main()
