#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STUDIO_ROOT = os.path.abspath(os.path.join(REPO, "..", "..", ".."))
RR = os.path.join(STUDIO_ROOT, "games", "RascalRally", "code")

CONTROL_TYPES = "src/ui/control_types.luau"
FACET_INIT = "src/init.luau"

SCANNED_ROOTS = ("examples/", "bench/", "tests/", "docs/")

EXCLUDED_TREES = (
    ("artifacts/", "frozen gate evidence records the call shape it was earned under"),
    ("docs/superpowers/", "the frozen original design specs and plans"),
    ("docs/plans/", "dated plans record the API they were written against"),
    (".superpowers/", "git-ignored controller scratch"),
)

UI_MEMBER = re.compile(r"(?<![\w.\"])(?:[A-Za-z_]\w*\.)?UI\.([A-Za-z_]\w*)")
FACET_MEMBER = re.compile(r"(?<![\w\"])Facet\.([A-Za-z_]\w*)")
APP_MEMBER = re.compile(
    r"(?<![\w.])app\.(controls|presentModal|installTheme|environment|core|present)\b"
)
SCAFFOLD = re.compile(r"(?<![\w])(newPresenter|newActionSystem|newFocusGraph|newCore|createHost)\s*\(")
TWO_ARG = re.compile(r"([A-Za-z_][A-Za-z0-9_.]*)\.new([A-Z][A-Za-z0-9_]*)\s*\(\s*\1\s*,")
COLON = re.compile(r":new[A-Z][A-Za-z0-9_]*\s*\(")
FENCE = re.compile(r"^\s*```\s*(lua|luau)\s*$")
FENCE_END = re.compile(r"^\s*```\s*$")
HOST_CREATE = re.compile(r"Roblox\.createHost\s*\(")

ALLOWLIST = [
    ("tests/native_parity_apps.spec.luau", re.compile(r"Facet\.nonexistentExport"),
     "the apps spec feeds a made-up export to its own missing-export scanner"),
    ("tools/check_call_shape_drift.py", re.compile(r"."),
     "the guard's own match data and planted selftest calls"),
    ("tests/native_public_surface.spec.luau", re.compile(r"toBeNil\(\)"),
     "the public-surface spec asserts that each removed name is nil"),
    ("tests/native_registration.spec.luau", re.compile(r"\bUI\.ProofControl\b"),
     "the registration spec generates ProofControl into an edited copy of src/ui/init.luau "
     "and proves the new constructor is exported"),
    ("tests/scenario_require_paths.spec.luau",
     re.compile(r"GetService\(\"ReplicatedStorage\"\)\.Facet\.tokens\.chrome_slots"),
     "a planted require line for the require-path checker names an Instance path under "
     "ReplicatedStorage, not the Facet table"),
]

SKIPPED_TREES = []


def read(rel):
    with open(os.path.join(REPO, rel), encoding="utf-8") as fh:
        return fh.read()


def public_controls():
    source = read(CONTROL_TYPES)
    match = re.search(r"export type Controls = \{(.*?)\n\}", source, re.S)
    if match is None:
        print(f"check_call_shape_drift: FAIL_ENVIRONMENT no Controls type in {CONTROL_TYPES}")
        sys.exit(2)
    names = set(re.findall(r"^\t([A-Za-z_]\w*):", match.group(1), re.M))
    if not names:
        print(f"check_call_shape_drift: FAIL_ENVIRONMENT empty Controls type in {CONTROL_TYPES}")
        sys.exit(2)
    return names


def facet_members():
    source = read(FACET_INIT)
    match = re.search(r"table\.freeze\(\{(.*?)\n\t*\}\)\n\t*return surface", source, re.S)
    if match is None:
        print(f"check_call_shape_drift: FAIL_ENVIRONMENT no export table in {FACET_INIT}")
        sys.exit(2)
    names = set(re.findall(r"^\t\t([A-Za-z_]\w*)\s*=", match.group(1), re.M))
    names |= set(re.findall(r"^export type ([A-Za-z_]\w*)", source, re.M))
    return names


def listed(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(f"check_call_shape_drift: FAIL_ENVIRONMENT git ls-files in {repo}")
        sys.exit(2)
    return sorted(set(out.stdout.splitlines()))


def allowed(scope_path, line_text):
    for path, pattern, _reason in ALLOWLIST:
        if scope_path == path or scope_path.startswith(path.rstrip("/") + "/"):
            if pattern.search(line_text):
                return True
    return False


def code_of(scope_path, source):
    if not scope_path.endswith(".md"):
        return source
    lines = source.split("\n")
    kept = []
    inside = False
    for line in lines:
        if inside:
            if FENCE_END.match(line):
                inside = False
                kept.append("")
            else:
                kept.append(line)
        else:
            inside = FENCE.match(line) is not None
            kept.append("")
    return "\n".join(kept)


def scan_source(scope_path, source, hits, controls, members):
    code = code_of(scope_path, source)
    lines = code.split("\n")

    def report(index, message):
        line = code.count("\n", 0, index) + 1
        text = lines[line - 1] if line - 1 < len(lines) else ""
        if not allowed(scope_path, text):
            hits.append(f"{scope_path}:{line}: {message}")

    for m in UI_MEMBER.finditer(code):
        if m.group(1) not in controls:
            report(m.start(), f"`UI.{m.group(1)}` is not a constructor on Facet.controls(runtime)")
    for m in FACET_MEMBER.finditer(code):
        if m.group(1) not in members:
            report(m.start(), f"`Facet.{m.group(1)}` is not exported by {FACET_INIT}")
    for m in APP_MEMBER.finditer(code):
        report(m.start(), f"`app.{m.group(1)}` belongs to the removed Facet application object")
    for m in SCAFFOLD.finditer(code):
        prefix = code[max(0, m.start() - 16):m.end()]
        if m.group(1) == "createHost" and HOST_CREATE.search(prefix):
            continue
        report(m.start(), f"`{m.group(1)}(` is removed Facet scaffolding")
    for m in TWO_ARG.finditer(code):
        report(m.start(), f"flat builder `{m.group(1)}.new{m.group(2)}({m.group(1)}, ...)` was removed")
    for m in COLON.finditer(code):
        report(m.start(), "colon builder `:new<Name>(` was removed")


def scan_file(abs_path, scope_path, hits, controls, members):
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            source = fh.read()
    except OSError:
        return
    scan_source(scope_path, source, hits, controls, members)


def in_scope(rel):
    if any(rel.startswith(prefix) for prefix, _reason in EXCLUDED_TREES):
        return False
    if not rel.startswith(SCANNED_ROOTS):
        return False
    if rel.startswith("docs/"):
        return rel.endswith((".md", ".luau"))
    return rel.endswith(".luau")


def scan_repo(repo, prefix, hits, controls, members):
    for rel in listed(repo):
        path = rel.replace("\\", "/")
        if not in_scope(path):
            continue
        abs_path = os.path.join(repo, rel)
        if os.path.isfile(abs_path):
            scan_file(abs_path, prefix + path, hits, controls, members)


def run_scan():
    hits = []
    del SKIPPED_TREES[:]
    controls = public_controls()
    members = facet_members()
    scan_repo(REPO, "", hits, controls, members)
    if os.path.isdir(RR) and subprocess.run(["git", "-C", RR, "ls-files"],
                                            capture_output=True, text=True).returncode == 0:
        scan_repo(RR, "rr:", hits, controls, members)
    else:
        SKIPPED_TREES.append("the consuming game's checkout")
    return hits


def selftest():
    controls = public_controls()
    members = facet_members()
    if "Button" not in controls or "Scene" in controls or "controls" not in members or "new" in members:
        print("check_call_shape_drift: SELFTEST FAIL - the public constructor sets were not read from source")
        return 1
    plants = {
        "examples/call_shape_probe_tmp.luau":
            "local UI = Facet.controls(runtime)\nreturn UI.Scene(\"Column\")({\n\tUI.Button({ label = \"Go\" }),\n})\n",
        "bench/call_shape_facet_probe_tmp.luau": "local app = Facet.new()\nreturn app\n",
        "tests/call_shape_app_probe_tmp.luau": "app.presentModal(function() end)\nreturn nil\n",
        "examples/call_shape_wrapped_probe_tmp.luau": "local x = Facet.newTable(\n\tFacet,\n\tcore,\n\t{}\n)\nreturn x\n",
        "docs/call_shape_probe_tmp.md":
            "# Probe\n\n`UI.Scene` in prose is not code.\n\n```luau\nlocal row = UI.Scene({})\n```\n",
        "tests/native_public_surface.spec.luau": "local row = UI.Scene({})\n",
    }
    expected = {
        "examples/call_shape_probe_tmp.luau": ["examples/call_shape_probe_tmp.luau:2: `UI.Scene`"],
        "bench/call_shape_facet_probe_tmp.luau": ["bench/call_shape_facet_probe_tmp.luau:1: `Facet.new`"],
        "tests/call_shape_app_probe_tmp.luau": ["tests/call_shape_app_probe_tmp.luau:1: `app.presentModal`"],
        "examples/call_shape_wrapped_probe_tmp.luau": ["examples/call_shape_wrapped_probe_tmp.luau:1: flat builder"],
        "docs/call_shape_probe_tmp.md": ["docs/call_shape_probe_tmp.md:6: `UI.Scene`"],
        "tests/native_public_surface.spec.luau": ["tests/native_public_surface.spec.luau:1: `UI.Scene`"],
    }
    tempdir = tempfile.mkdtemp(prefix="call_shape_selftest_")
    real = []
    failures = []
    try:
        for scope, content in plants.items():
            hits = []
            if scope == "tests/native_public_surface.spec.luau":
                path = os.path.join(tempdir, "allowlist_scope.luau")
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(content)
            else:
                path = os.path.join(REPO, scope)
                real.append(path)
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(content)
            scan_file(path, scope, hits, controls, members)
            for needle in expected[scope]:
                if not any(h.startswith(needle) for h in hits):
                    failures.append(f"{scope}: expected {needle!r}, got {hits}")
            if scope == "docs/call_shape_probe_tmp.md" and len(hits) != 1:
                failures.append(f"{scope}: prose outside a fence was scanned: {hits}")
            if scope == "examples/call_shape_probe_tmp.luau" and len(hits) != 1:
                failures.append(f"{scope}: a public constructor was reported: {hits}")
        planted = run_scan()
        for scope in plants:
            if scope != "tests/native_public_surface.spec.luau" and not any(h.startswith(scope) for h in planted):
                failures.append(f"the full scan missed the planted file {scope}")
    finally:
        for path in real:
            if os.path.exists(path):
                os.unlink(path)
        for name in os.listdir(tempdir):
            os.unlink(os.path.join(tempdir, name))
        os.rmdir(tempdir)
    if failures:
        print("check_call_shape_drift: SELFTEST FAIL - a planted removed call survived")
        print("\n".join(failures))
        return 1
    clean = run_scan()
    if clean:
        print("check_call_shape_drift: SELFTEST FAIL - restored tree not clean:")
        print("\n".join(clean[:20]))
        return 1
    print("check_call_shape_drift: SELFTEST PASS - planted UI.Scene, Facet.new, app.presentModal, a wrapped "
          "flat builder and a fenced docs UI.HStack each caught by file scan and full scan; prose and "
          "public constructors not reported; an allowlist pattern outside its line still caught; "
          "restored tree clean")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    hits = run_scan()
    if hits:
        print(f"check_call_shape_drift: FAIL - {len(hits)} removed call site(s) outside the allowlist:")
        for h in hits[:60]:
            print("  " + h)
        if len(hits) > 60:
            print(f"  ... and {len(hits) - 60} more")
        sys.exit(1)
    print("check_call_shape_drift: PASS - examples, bench, tests and docs code blocks call only "
          "constructors on Facet.controls(runtime) and members exported by src/init.luau")
    for tree in SKIPPED_TREES:
        print(f"  NOT SCANNED: {tree} is not beside this checkout")


if __name__ == "__main__":
    main()
