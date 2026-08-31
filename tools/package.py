#!/usr/bin/env python3
"""package — the one maintainer interface to Facet's Roblox Package release channel.

GIT IS CANONICAL. Facet ships as ONE official Roblox Package with a stable asset
id, and every fact about a release is derived from the repository: the version
from `src/init.luau`, the commit from `git rev-parse HEAD`, the source hash from
the `src/**/*.luau` tree itself. Nothing here invents a number, and nothing here
trusts a number a human typed without checking it against the repository first.

WHAT THIS FILE IS. `tools/package.sh` is a three-line wrapper; this is the
program. It has no dependencies outside the Python standard library, and its
network layer is `urllib` behind ONE function (`_api`) so a fake transport is
total — a test can drive create/publish end to end and no packet leaves the
machine.

    tools/package.sh build      # rebuild build/Facet.rbxm + build/Facet.manifest.json
    tools/package.sh status     # this tree vs the last receipt: drift, dirt, semver
    tools/package.sh verify     # build + tree inspection + purity + packaged canary
    tools/package.sh create     # mint the asset (DRY RUN unless --confirm)
    tools/package.sh publish    # push a revision (DRY RUN unless --confirm)
    tools/package.sh rollback   # print both rollback procedures; never uploads
    tools/package.sh stamp      # record a human's Studio verification on a receipt

`build`, `status` and `verify` are offline and are the default working commands.
`create` and `publish` print exactly what they WOULD send and every guard's
verdict, then exit without touching the network. `--confirm` is the only way a
request is ever made, and it is refused unless every guard passes.

THE TWO ROUTES, AND WHY THERE ARE TWO. The platform research note
(`artifacts/distribution-readiness/research/platform-sources.md`, fetched
2026-08-30) found the bridge between Open Cloud and Studio Packages is one
sentence — the Assets API's supported-types table says a Model "Will be uploaded
as packages" — and that the same guide says "Currently, you can only update the
asset content for `.fbx` files." Facet's artifact is an `.rbxm`. So the API's
CREATE path is documented for our file type and its UPDATE path is not, and
Roblox separately warns that "`.rbxm` or `.rbxmx` files edited outside of Roblox
Studio might not upload or function." One interface, two routes, selected by
`route` in `package/facet-package.json`:

  * `open-cloud` — POST /v1/assets to create, PATCH /v1/assets/{id} to publish,
    polling GET /v1/operations/{id}. Implemented in full; unproved for `.rbxm`
    until the post-checkpoint Studio spike says otherwise.
  * `studio` (the default) — build the canonical publisher place
    `build/FacetPublisher.rbxl`, print the exact Convert-to-Package /
    Publish-to-Package steps, and then use the API only to READ: verify the asset
    on create, poll `GET /v1/assets/{id}/versions` for the new version on publish.

Both routes run the SAME guards before a single instruction is printed or a
single call is made.

THE SECRET RULE. `ROBLOX_API_KEY` is read from the environment and from nowhere
else — never a keys file, never a cookie, never an argument. It is never printed,
never written to a receipt, and never logged. The only thing this program will
ever say about it is whether it is set.

Exit codes: 0 success (a dry run is a success even when it lists refusals — the
report IS the product), 1 a refusal or a failed check, 2 an environment failure.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

#[[ THE INTERPRETER FLOOR, AND WHY IT IS A COMMENT AS MUCH AS A CHECK.
#
#   `tools/build_model.sh` calls `python3`, and on a fresh clone that can resolve
#   to the system interpreter — /usr/bin/python3 is 3.9.6 on current macOS — not
#   to whatever a developer has on PATH. This file therefore has to PARSE on 3.9,
#   and one line of it did not: a PEP-701 f-string (`f"{shown(result["path"])}"`,
#   nested same quotes) is 3.12-only syntax and raised
#   `SyntaxError: f-string: unmatched '['` at compile time, which surfaced as an
#   unexplained model-build failure rather than as anything about Python.
#
#   A runtime guard cannot catch that class: a SyntaxError happens before the
#   first statement runs. So the real protection is the STYLE RULE — no syntax
#   newer than 3.8 in this file — and the check below is for the other half, an
#   interpreter that parses the file but is too old to run it. Keep both.
if sys.version_info < (3, 8):
    sys.stderr.write(
        "package: this tool needs Python 3.8 or newer; the interpreter running it is "
        "{}.{}.{} at {}\n".format(sys.version_info[0], sys.version_info[1], sys.version_info[2], sys.executable)
    )
    raise SystemExit(2)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "src")
BUILD = os.path.join(REPO, "build")
BUILD_MODEL = os.path.join(HERE, "build_model.sh")
PURITY = os.path.join(HERE, "check_library_purity.py")
CANARY = "tools/lune/package_canary.luau"

DEFAULT_CONFIG = os.path.join(REPO, "package", "facet-package.json")
DEFAULT_RECEIPTS = os.path.join(REPO, "package", "receipts")
GATE_EVIDENCE = os.path.join(REPO, "artifacts", "verify", "latest-release.json")

DEFAULT_MODEL = os.path.join(BUILD, "Facet.rbxm")
DEFAULT_XML = os.path.join(BUILD, "Facet.rbxmx")
DEFAULT_MANIFEST = os.path.join(BUILD, "Facet.manifest.json")
PUBLISHER_PLACE = os.path.join(BUILD, "FacetPublisher.rbxl")

API_BASE = "https://apis.roblox.com/assets"
RBXM_CONTENT_TYPE = "model/x-rbxm"
ASSET_TYPE = "Model"

BUILD_SCHEMA = "facet-package/1"
MANIFEST_SCHEMA = "facet-package-manifest/1"
RECEIPT_SCHEMA = "facet-package-receipt/1"
GATE_SCHEMA = "facet-verify-run/1"

# The names that must never reach the distribution. `check_library_purity.py`
# guards the THEME claim (studio-neutral); this guards the CONTENT claim. Kept
# here rather than derived, because the point of the list is that a human decided
# each entry — the Fusion adapter and the imperative core are rejected bake-off
# artifacts (execution plan §0), and tests/examples/bench/vendor are development
# material a consumer must never receive.
FORBIDDEN_SEGMENTS = ("tests", "examples", "vendor", "bench", "spikes")
FORBIDDEN_SUBSTRINGS = ("fusion_adapter", "imperative", ".spec")

# The moderation values a read-back may carry and still be a release. The schema
# table says `Approved`; the usage guide's worked example says
# `MODERATION_STATE_APPROVED`. The docs disagree with each other (research note
# §1.6) so both spellings are accepted and nothing else is.
APPROVED_MODERATION = ("Approved", "MODERATION_STATE_APPROVED")


# ── plain repository facts ───────────────────────────────────────────────────


def env_with_tools():
    e = dict(os.environ)
    e["PATH"] = os.path.expanduser("~/.rokit/bin") + ":/opt/homebrew/bin:/usr/local/bin:" + e.get("PATH", "")
    return e


def run(args, **kwargs):
    return subprocess.run(args, cwd=REPO, env=env_with_tools(), capture_output=True, text=True, **kwargs)


def read_version():
    """`Facet.VERSION`, from the one place it is declared."""
    with open(os.path.join(SRC, "init.luau")) as handle:
        for line in handle:
            match = re.search(r'VERSION\s*=\s*"([^"]+)"', line)
            if match:
                return match.group(1)
    raise SystemExit("package: src/init.luau declares no VERSION")


def source_files():
    """Every shipped Luau module, repo-relative and sorted. Spec files are not
    shipped and `globIgnorePaths` keeps them out of the model, so they are out of
    the hash too: a test edit must not change the identity of the artifact."""
    out = []
    for base, _dirs, files in os.walk(SRC):
        for name in files:
            if name.endswith(".luau") and not name.endswith(".spec.luau"):
                out.append(os.path.relpath(os.path.join(base, name), REPO))
    return sorted(out)


def source_hash():
    """sha256 over the sorted source list: `<relpath>\\n` then the file's bytes
    with CRLF normalized to LF. Path-then-content means a rename changes the hash
    even when no byte of code moved, which is the honest answer — a rename moves
    an instance in the shipped tree."""
    digest = hashlib.sha256()
    for rel in source_files():
        with open(os.path.join(REPO, rel), "rb") as handle:
            body = handle.read().replace(b"\r\n", b"\n")
        digest.update(rel.encode("utf-8") + b"\n")
        digest.update(body)
    return digest.hexdigest()


def git(*args):
    result = run(["git"] + list(args))
    if result.returncode != 0:
        raise SystemExit(f"package: git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def head_commit():
    return git("rev-parse", "HEAD")


def porcelain(paths=None):
    return git(*(["status", "--porcelain"] + (["--"] + list(paths) if paths else [])))


def source_commit_stamp():
    """HEAD, suffixed `-dirty` when the SOURCE TREE has uncommitted work. Scoped
    to `src` deliberately: an artifact built while a doc or a test is being edited
    is still an exact build of a committed source tree, and saying otherwise would
    make the stamp meaningless on any working day."""
    commit = head_commit()
    return commit + "-dirty" if porcelain(["src"]) else commit


def shown(path):
    """Repo-relative when the path is inside the repository, absolute otherwise.
    A bare `os.path.relpath` turns a temp directory into a wall of `../`."""
    absolute = os.path.abspath(path)
    return os.path.relpath(absolute, REPO) if absolute.startswith(REPO + os.sep) else absolute


def read_bytes(path):
    with open(path, "rb") as handle:
        return handle.read()


def write_atomic(path, text):
    """Write through a unique temporary in the same directory, then rename.

    Every path this program writes is a path some concurrent producer may be
    READING — three of them run this build at once. `os.replace` is atomic within
    a filesystem, so a reader sees the old complete file or the new complete file
    and never the half-written one that made a concurrent build report "File
    contains no JSON value"."""
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        "w", dir=directory, prefix=os.path.basename(path) + ".tmp.", delete=False
    )
    try:
        handle.write(text)
        handle.close()
        os.replace(handle.name, path)
    except BaseException:
        handle.close()
        if os.path.exists(handle.name):
            os.unlink(handle.name)
        raise


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def toolchain():
    def version_of(tool):
        result = run([tool, "--version"])
        return result.stdout.strip() or result.stderr.strip() or "unknown"

    return {"rojo": version_of("rojo"), "lune": version_of("lune")}


def semver(text):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", str(text or ""))
    return tuple(int(part) for part in match.groups()) if match else None


# ── the staging directory the model builder mounts ───────────────────────────


def stage(out_root=None, quiet=False):
    """Generate `<out_root>/Distribution/` — regenerated on EVERY build, never
    edited by hand, never committed (`build/` is gitignored).

    THE STAGING DIRECTORY IS PER-INVOCATION, and `out_root` is required in
    practice: `tools/build_model.sh` passes one named after its own process.
    Sharing it is what made three concurrent builds fail — one process was
    `shutil.rmtree`-ing the directory while another was writing into it, which
    surfaces as `OSError: [Errno 66] Directory not empty` and says nothing at all
    about concurrency. Calling this with no `out_root` is the single-build
    convenience and uses a fresh temporary directory rather than a fixed one.

    It carries no build time. Reproducibility is the reason: two builds of the
    same commit must produce the same bytes, and a timestamp inside the artifact
    would make that impossible. The time of a release lives in its receipt, which
    is where a reader actually looks for it."""
    if out_root is None:
        out_root = tempfile.mkdtemp(prefix="facet-stage-")
    target = os.path.join(out_root, "Distribution")
    if os.path.isdir(target):
        shutil.rmtree(target)
    os.makedirs(target)

    meta = {
        "className": "Folder",
        "attributes": {
            "Version": read_version(),
            "SourceCommit": source_commit_stamp(),
            "SourceHash": source_hash(),
            "BuildSchema": BUILD_SCHEMA,
            "Repository": "https://github.com/josha/Facet",
        },
    }
    write_atomic(os.path.join(target, "init.meta.json"), json.dumps(meta, indent=2, sort_keys=True) + "\n")

    notes = []
    for source_name, staged_name in (("LICENSE", "LICENSE.txt"), ("THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.txt")):
        source_path = os.path.join(REPO, source_name)
        staged_path = os.path.join(target, staged_name)
        if os.path.isfile(source_path):
            shutil.copyfile(source_path, staged_path)
        else:
            # A MISSING NOTICE MUST NOT BREAK THE BUILD. The root LICENSE and
            # THIRD_PARTY_NOTICES are another workstream's deliverable; until they
            # land, the model still builds and the placeholder says plainly that
            # the file is owed. `verify` reports it, so it cannot ship unnoticed.
            with open(staged_path, "w") as handle:
                handle.write(f"{source_name} file pending\n")
            notes.append(source_name)
    if notes and not quiet:
        print(f"  stage: placeholder text for {', '.join(notes)} (root file not present yet)")
    return {"path": target, "placeholders": notes, "attributes": meta["attributes"]}


# ── the semantic manifest, read off the .rbxmx twin ──────────────────────────


def walk_model(xml_path):
    """Every instance in the built model: `{path, className, sourceSha256}`,
    sorted by path. Read from the XML twin because a binary `.rbxm` is LZ4-chunked
    — the same reason `check_library_purity.py` builds one."""
    entries = []

    def visit(item, prefix):
        name = item.get("class")
        source = None
        props = item.find("Properties")
        if props is not None:
            for prop in props:
                if prop.get("name") == "Name":
                    name = prop.text or name
                elif prop.get("name") == "Source":
                    source = prop.text or ""
        path = f"{prefix}/{name}" if prefix else name
        entry = {"path": path, "className": item.get("class")}
        if source is not None:
            entry["sourceSha256"] = hashlib.sha256(source.encode("utf-8")).hexdigest()
        entries.append(entry)
        for child in item.findall("Item"):
            visit(child, path)

    for item in ET.parse(xml_path).getroot().findall("Item"):
        visit(item, "")
    return sorted(entries, key=lambda entry: entry["path"])


def manifest_body_hash(instances):
    """The comparison basis. Rojo's output is byte-deterministic on this
    toolchain (measured: two builds of the same tree, identical sha256, both
    `.rbxm` and `.rbxmx`), so `artifactSha256` alone would do — but a body hash
    over the SEMANTIC content survives a future Rojo that reorders referents,
    and it is the number a human can reason about when a build drifts."""
    canonical = json.dumps(instances, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def write_manifest(xml_path, artifact_path, out_path):
    instances = walk_model(xml_path)
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "version": read_version(),
        "sourceCommit": source_commit_stamp(),
        "sourceHash": source_hash(),
        "artifact": shown(artifact_path),
        "artifactSha256": file_sha256(artifact_path),
        "instanceCount": len(instances),
        "moduleCount": sum(1 for entry in instances if entry["className"] == "ModuleScript"),
        "bodyHash": manifest_body_hash(instances),
        "instances": instances,
    }
    write_atomic(out_path, json.dumps(manifest, indent=2) + "\n")
    return manifest


def load_manifest(path=DEFAULT_MANIFEST):
    if not os.path.isfile(path):
        return None
    with open(path) as handle:
        return json.load(handle)


# ── build ────────────────────────────────────────────────────────────────────


def build_model(output=None, publisher=False, quiet=False):
    """Run the ONE model builder. There is no second Rojo mapping anywhere in
    this file, and there must never be: a builder living beside the check would
    prove the check rather than the artifact."""
    args = [BUILD_MODEL]
    if output:
        args.append(output)
    if publisher:
        args.append("--publisher")
    result = run(args)
    if result.returncode != 0:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(2)
    if not quiet:
        sys.stdout.write(result.stdout)
    return result


# ── the expected shipped tree ────────────────────────────────────────────────


def expected_tree():
    """The instance tree `src/` must produce: `Facet` at the root, one
    ModuleScript per shipped `.luau`, one Folder per directory on the way."""
    modules, folders = {}, set()
    for rel in source_files():
        parts = rel.split(os.sep)
        rest = parts[1:]
        if rest == ["init.luau"]:
            modules["Facet"] = rel
            continue
        accumulated = "Facet"
        for directory in rest[:-1]:
            accumulated = f"{accumulated}/{directory}"
            folders.add(accumulated)
        modules[f"{accumulated}/{rest[-1][: -len('.luau')]}"] = rel
    return modules, folders


ALLOWED_EXTRA = {
    "Facet/Distribution": "Folder",
    "Facet/Distribution/LICENSE": "StringValue",
    "Facet/Distribution/THIRD_PARTY_NOTICES": "StringValue",
}


def inspect_tree(manifest):
    """Two questions, both of which have to be asked. Is every runtime module
    PRESENT (a missing one is a Package that does not load), and is anything
    else present (an extra one is a development file a consumer receives)."""
    modules, folders = expected_tree()
    present = {entry["path"]: entry for entry in manifest["instances"]}
    problems = []

    for path in sorted(modules):
        entry = present.get(path)
        if entry is None:
            problems.append(f"missing from the model: {path} (from {modules[path]})")
        elif entry["className"] != "ModuleScript":
            problems.append(f"{path} is a {entry['className']}, not a ModuleScript")
    for path in sorted(folders):
        entry = present.get(path)
        if entry is None:
            problems.append(f"missing from the model: folder {path}")

    known = set(modules) | folders | set(ALLOWED_EXTRA)
    for path in sorted(present):
        if path not in known:
            problems.append(f"UNEXPECTED instance in the model: {path} ({present[path]['className']})")
        elif path in ALLOWED_EXTRA and present[path]["className"] != ALLOWED_EXTRA[path]:
            problems.append(f"{path} is a {present[path]['className']}, expected {ALLOWED_EXTRA[path]}")

    for path in sorted(present):
        segments = path.split("/")
        for segment in segments:
            if segment in FORBIDDEN_SEGMENTS:
                problems.append(f"FORBIDDEN in the distribution: {path} (segment '{segment}')")
        lowered = path.lower()
        for needle in FORBIDDEN_SUBSTRINGS:
            if needle in lowered:
                problems.append(f"FORBIDDEN in the distribution: {path} (contains '{needle}')")

    return problems, {"modules": len(modules), "folders": len(folders), "instances": len(present)}


# ── config and receipts ──────────────────────────────────────────────────────


def load_config(path):
    if not os.path.isfile(path):
        raise SystemExit(f"package: no config at {path}")
    with open(path) as handle:
        return json.load(handle)


def save_config(path, config):
    write_atomic(path, json.dumps(config, indent=2) + "\n")


def receipts(directory):
    if not os.path.isdir(directory):
        return []
    files = [os.path.join(directory, name) for name in sorted(os.listdir(directory)) if name.endswith(".json")]
    out = []
    for path in files:
        with open(path) as handle:
            try:
                out.append((path, json.load(handle)))
            except ValueError:
                continue
    out.sort(key=lambda pair: pair[1].get("publishedAt") or "")
    return out


def latest_receipt(directory):
    found = receipts(directory)
    return found[-1][1] if found else None


def gate_identity(version, commit, source_hash_value):
    """The release-gate identity this channel expects. D7's coordinator computes
    identity over its own normalized inputs; the package channel needs a name for
    "this exact release", and this is it. Published as `package.sh` subcommand
    `identity` so the coordinator can stamp the same string rather than guess."""
    material = f"facet-release-gate/1|{version}|{commit}|{source_hash_value}"
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def read_gate_evidence(path=GATE_EVIDENCE):
    if not os.path.isfile(path):
        return None
    with open(path) as handle:
        try:
            return json.load(handle)
        except ValueError:
            return {"schema": "unreadable"}


# ── the guards, as one pure function ─────────────────────────────────────────
#
# `decide` takes FACTS and returns REFUSALS. It reads no file, makes no call and
# prints nothing, which is the only reason every refusal below can be proven by a
# test that runs in milliseconds and never touches a network.


class Refusal:
    def __init__(self, code, message):
        self.code = code
        self.message = message

    def __repr__(self):
        return f"Refusal({self.code})"


def decide(facts):
    op = facts["op"]
    out = []

    def refuse(code, message):
        out.append(Refusal(code, message))

    if not facts.get("api_key_present"):
        refuse(
            "api-key-missing",
            "ROBLOX_API_KEY is not set in the environment. It is read from the environment ONLY — "
            "never a keys file, never a cookie — and it is never printed or written to a receipt.",
        )

    if facts.get("git_dirty"):
        refuse("dirty-tree", "the working tree has uncommitted changes; a release must be an exact commit")

    arg_commit = facts.get("arg_commit")
    if not arg_commit:
        refuse("commit-mismatch", "--commit <sha> is required and must equal HEAD")
    elif arg_commit != facts.get("head_commit"):
        refuse("commit-mismatch", f"--commit {arg_commit} is not HEAD ({facts.get('head_commit')})")

    arg_version = facts.get("arg_version")
    if not arg_version:
        refuse("version-mismatch", "--version <x.y.z> is required and must equal Facet.VERSION")
    elif arg_version != facts.get("source_version"):
        refuse("version-mismatch", f"--version {arg_version} is not Facet.VERSION ({facts.get('source_version')})")

    if facts.get("fresh_build_hash") != facts.get("manifest_hash"):
        refuse(
            "build-drift",
            f"a fresh build hashes {facts.get('fresh_build_hash')} but build/Facet.manifest.json records "
            f"{facts.get('manifest_hash')}; the recorded manifest is stale",
        )

    creator = facts.get("config_creator") or {}
    if not creator.get("type") or not creator.get("id"):
        refuse("creator-unset", "package/facet-package.json has no creator; it is filled at the owner checkpoint")
    else:
        if facts.get("arg_creator_type") and facts["arg_creator_type"] != creator["type"]:
            refuse("creator-mismatch", f"--creator-type {facts['arg_creator_type']} != configured {creator['type']}")
        if facts.get("arg_creator_id") and str(facts["arg_creator_id"]) != str(creator["id"]):
            refuse("creator-mismatch", f"--creator-id {facts['arg_creator_id']} != configured {creator['id']}")

    config_asset = facts.get("config_asset_id")
    arg_asset = facts.get("arg_asset_id")
    if op == "create":
        if config_asset:
            refuse(
                "asset-id-present",
                f"package/facet-package.json already records assetId {config_asset}; create is one-time. "
                f"Use publish to push a revision.",
            )
    else:
        if not config_asset:
            refuse("asset-id-missing", "package/facet-package.json records no assetId; run create first")
        elif arg_asset and str(arg_asset) != str(config_asset):
            refuse("asset-id-mismatch", f"--asset-id {arg_asset} != configured {config_asset}")

    gate = facts.get("gate")
    if not gate:
        refuse(
            "gate-evidence-missing",
            f"no release-gate evidence at {shown(GATE_EVIDENCE)}; the release tier must run first",
        )
    elif gate.get("status") != "PASS":
        refuse("gate-evidence-failed", f"release-gate evidence status is {gate.get('status')!r}, not PASS")
    elif gate.get("identity") != facts.get("current_identity"):
        refuse(
            "gate-identity-mismatch",
            f"release-gate evidence is for identity {gate.get('identity')}, this release is "
            f"{facts.get('current_identity')}",
        )

    receipt = facts.get("latest_receipt")
    if receipt and receipt.get("operationPath") and not receipt.get("assetRevision"):
        refuse(
            "operation-in-flight",
            f"receipt for {receipt.get('version')} records operation {receipt.get('operationPath')} with no "
            f"assetRevision; resolve that operation before starting another",
        )

    cloud = facts.get("cloud_revision")
    if cloud and receipt:
        known = (receipt.get("assetRevision") or {}).get("revisionId")
        seen = cloud.get("revisionId")
        if known is None or (seen is not None and str(seen) != str(known)):
            refuse(
                "cloud-revision-newer",
                f"the cloud asset is at revision {seen} but the newest receipt knows {known}; something published "
                f"outside this tool",
            )

    if receipt:
        last = semver(receipt.get("version"))
        current = semver(facts.get("source_version"))
        if last and current:
            if current < last:
                refuse("version-not-advanced", f"VERSION {facts['source_version']} is behind the last receipt's {receipt['version']}")
            elif current == last:
                if receipt.get("sourceHash") != facts.get("source_hash"):
                    refuse(
                        "version-hash-conflict",
                        f"VERSION {facts['source_version']} was already published from source hash "
                        f"{receipt.get('sourceHash')}; this tree hashes {facts.get('source_hash')}",
                    )
                else:
                    refuse("version-not-advanced", f"VERSION {facts['source_version']} did not advance past the last receipt")

    moderation = facts.get("moderation")
    if moderation is not None and moderation not in APPROVED_MODERATION:
        refuse("moderation-not-approved", f"the asset's moderation state reads {moderation!r}, not approved")

    return out


# ── the transport seam ───────────────────────────────────────────────────────


class HttpTransport:
    """The only code in this program that opens a socket."""

    name = "https"

    def request(self, method, url, headers, body=None):
        request = urllib.request.Request(url, data=body, method=method)
        for key, value in headers.items():
            request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                raw, status = response.read(), response.status
        except urllib.error.HTTPError as error:
            raw, status = error.read(), error.code
        except urllib.error.URLError as error:
            raise SystemExit(f"package: network failure calling {method} {url}: {error.reason}")
        try:
            return status, json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return status, {"raw": raw[:512].decode("utf-8", "replace")}


class FakeTransport:
    """Canned responses, matched in order by (method, url fragment). Every
    unmatched call is an error rather than a default, so a test that drifts from
    the shape it claims to exercise fails instead of passing quietly."""

    name = "fake"

    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    def request(self, method, url, headers, body=None):
        self.calls.append({"method": method, "url": url, "bodyBytes": len(body or b"")})
        for index, (want_method, fragment, status, payload) in enumerate(self.script):
            if want_method == method and fragment in url:
                del self.script[index]
                return status, payload
        raise RuntimeError(f"fake transport: nothing canned for {method} {url}")


def multipart(fields, files):
    """`request` (JSON) + `fileContent` (binary), per the Assets API's own curl
    sample. Hand-rolled because the standard library has no multipart encoder and
    this program takes no dependencies."""
    boundary = "----FacetPackage" + hashlib.sha256(str(time.time()).encode()).hexdigest()[:24]
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += value.encode("utf-8") + b"\r\n"
    for name, (filename, content_type, payload) in files.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode()
        body += f"Content-Type: {content_type}\r\n\r\n".encode()
        body += payload + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def _api(transport, method, path, api_key, body=None, content_type=None):
    """THE one seam. Every request in this file goes through here, which is what
    makes `FakeTransport` total rather than partial."""
    url = API_BASE + path
    headers = {"x-api-key": api_key, "Accept": "application/json"}
    if content_type:
        headers["Content-Type"] = content_type
    return transport.request(method, url, headers, body)


def poll_operation(transport, operation_path, api_key, timeout=600, quiet=False):
    """`GET /v1/operations/{id}` until `done`. The docs give no recommended
    interval for this endpoint (research note §1.6), so this backs off 1→15s and
    stops at `timeout` rather than inventing a platform guarantee."""
    operation_id = operation_path.split("/")[-1]
    deadline = time.time() + timeout
    delay = 1.0
    while time.time() < deadline:
        status, payload = _api(transport, "GET", f"/v1/operations/{operation_id}", api_key)
        if status != 200:
            return status, payload
        if payload.get("done"):
            return status, payload
        if not quiet:
            print(f"  operation {operation_id}: not done, retrying in {delay:.0f}s")
        time.sleep(delay)
        delay = min(delay * 2, 15.0)
    return 408, {"error": {"message": f"operation {operation_id} did not complete within {timeout}s"}}


# ── shared release plumbing ──────────────────────────────────────────────────


def gather_facts(op, args, config, receipts_dir, transport=None, api_key=None):
    """Everything `decide` needs, read once. The cloud reads happen here and only
    when a key exists AND an asset id exists — a dry run with no key never
    contacts anything."""
    version = read_version()
    commit = head_commit()
    source_hash_value = source_hash()
    identity = gate_identity(version, commit, source_hash_value)

    build_model(quiet=True)
    fresh = write_manifest(DEFAULT_XML, DEFAULT_MODEL, DEFAULT_MANIFEST)

    config_asset = config.get("assetId")
    cloud_revision, moderation = None, None
    if transport is not None and api_key and config_asset:
        status, payload = _api(transport, "GET", f"/v1/assets/{config_asset}", api_key)
        if status == 200:
            cloud_revision = {
                "revisionId": payload.get("revisionId"),
                "revisionCreateTime": payload.get("revisionCreateTime"),
            }
            moderation = (payload.get("moderationResult") or {}).get("moderationState")

    return {
        "op": op,
        "api_key_present": bool(api_key),
        "git_dirty": bool(porcelain()),
        "arg_commit": getattr(args, "commit", None),
        "head_commit": commit,
        "arg_version": getattr(args, "version", None),
        "source_version": version,
        "source_hash": source_hash_value,
        "fresh_build_hash": fresh["bodyHash"],
        "manifest_hash": fresh["bodyHash"],
        "config_creator": config.get("creator") or {},
        "arg_creator_type": getattr(args, "creator_type", None),
        "arg_creator_id": getattr(args, "creator_id", None),
        "config_asset_id": config_asset,
        "arg_asset_id": getattr(args, "asset_id", None),
        "gate": read_gate_evidence(),
        "current_identity": identity,
        "latest_receipt": latest_receipt(receipts_dir),
        "cloud_revision": cloud_revision,
        "moderation": moderation,
        "_manifest": fresh,
    }


def print_verdicts(facts, refusals):
    print("")
    print("GUARDS")
    codes = {refusal.code for refusal in refusals}
    checked = [
        ("api key present (environment only)", "api-key-missing"),
        ("working tree clean", "dirty-tree"),
        ("--commit == HEAD", "commit-mismatch"),
        ("--version == Facet.VERSION", "version-mismatch"),
        ("fresh build matches the recorded manifest", "build-drift"),
        ("creator configured", "creator-unset"),
        ("creator argument matches config", "creator-mismatch"),
        ("create only when no asset id exists", "asset-id-present"),
        ("publish only when an asset id exists", "asset-id-missing"),
        ("asset id argument matches config", "asset-id-mismatch"),
        ("release-gate evidence present", "gate-evidence-missing"),
        ("release-gate evidence green", "gate-evidence-failed"),
        ("release-gate evidence at this identity", "gate-identity-mismatch"),
        ("no operation in flight", "operation-in-flight"),
        ("cloud revision not ahead of the receipts", "cloud-revision-newer"),
        ("VERSION advanced under semver", "version-not-advanced"),
        ("VERSION not reused with different source", "version-hash-conflict"),
        ("moderation approved", "moderation-not-approved"),
    ]
    seen = set()
    for label, code in checked:
        if (label, code) in seen:
            continue
        seen.add((label, code))
        print(f"  [{'REFUSE' if code in codes else '  ok  '}] {label}")
    if refusals:
        print("")
        print(f"REFUSALS ({len(refusals)})")
        for refusal in refusals:
            print(f"  - {refusal.code}: {refusal.message}")
    else:
        print("")
        print("REFUSALS (0) — every guard passes")


def describe_request(method, path, request_json, file_path):
    print("")
    print("REQUEST THAT WOULD BE SENT")
    print(f"  {method} {API_BASE}{path}")
    print("  headers: x-api-key: <redacted — never printed>, Accept: application/json")
    print("  body: multipart/form-data")
    print(f"    part 'request'     (application/json): {json.dumps(request_json)}")
    if file_path:
        print(
            f"    part 'fileContent' ({RBXM_CONTENT_TYPE}): {shown(file_path)} "
            f"({os.path.getsize(file_path)} bytes, sha256 {file_sha256(file_path)}) — contents not shown"
        )


def creation_context(config):
    """`userId` for an individual, `groupId` for a group — and a legible
    placeholder while the owner checkpoint has not chosen. Ownership cannot be
    transferred afterwards (Packages doc: "Ownership transfers are not supported
    by the asset system"), so this field is a one-way decision and a dry run must
    show plainly that it has not been made."""
    creator = config.get("creator") or {}
    if not creator.get("type") or not creator.get("id"):
        return {"creator": {"<userId or groupId>": "<unset — owner checkpoint>"}}
    key = "userId" if creator.get("type") == "user" else "groupId"
    return {"creator": {key: str(creator.get("id"))}}


def write_receipt(receipts_dir, config, facts, *, operation_path, asset_revision, moderation, actor, gate, extra=None):
    version = facts["source_version"]
    commit = facts["head_commit"]
    receipt = {
        "schema": RECEIPT_SCHEMA,
        "version": version,
        "sourceCommit": commit,
        "sourceHash": facts["source_hash"],
        "artifactSha256": facts["_manifest"]["artifactSha256"],
        "assetId": config.get("assetId"),
        "operationId": (operation_path or "").split("/")[-1] or None,
        "operationPath": operation_path,
        "assetRevision": asset_revision,
        "moderation": moderation,
        "publishedAt": now_iso(),
        "actor": actor,
        "route": config.get("route"),
        "toolchain": toolchain(),
        "gateRun": {"identity": (gate or {}).get("identity"), "status": (gate or {}).get("status")},
        "studio_verification": {"status": "pending", "by": None, "date": None, "notes": None},
    }
    if extra:
        receipt.update(extra)
    os.makedirs(receipts_dir, exist_ok=True)
    path = os.path.join(receipts_dir, f"{version}-{commit[:7]}.json")
    write_atomic(path, json.dumps(receipt, indent=2) + "\n")
    return path, receipt


def record_version(config_path, config, receipt):
    """Append this publish to the config's `versions` list. The receipt is the
    record of a release; this is the SUMMARY a reader of the public manifest sees
    without opening a directory of receipts — version, commit, revision, when."""
    config.setdefault("versions", []).append(
        {
            "version": receipt["version"],
            "sourceCommit": receipt["sourceCommit"],
            "assetRevision": (receipt.get("assetRevision") or {}).get("revisionId"),
            "publishedAt": receipt["publishedAt"],
        }
    )
    save_config(config_path, config)


def api_key_from_env():
    key = os.environ.get("ROBLOX_API_KEY") or ""
    return key.strip() or None


# ── commands ─────────────────────────────────────────────────────────────────


def cmd_stage(args):
    result = stage(args.out, quiet=args.quiet)
    if not args.quiet:
        print(f"staged {shown(result['path'])}")
    return 0


def cmd_manifest(args):
    manifest = write_manifest(args.model, args.artifact, args.out)
    print(
        f"manifest {shown(args.out)}: {manifest['instanceCount']} instances "
        f"({manifest['moduleCount']} modules), body {manifest['bodyHash'][:12]}"
    )
    return 0


def cmd_build(args):
    build_model(publisher=args.publisher)
    manifest = load_manifest()
    if manifest is None:
        print("package build: the builder produced no manifest")
        return 1
    print(
        f"  version {manifest['version']}  commit {manifest['sourceCommit']}\n"
        f"  sourceHash   {manifest['sourceHash']}\n"
        f"  artifactSha  {manifest['artifactSha256']}\n"
        f"  manifest     {manifest['instanceCount']} instances, {manifest['moduleCount']} modules, "
        f"body {manifest['bodyHash']}"
    )
    return 0


def cmd_status(args):
    build_model(quiet=True)
    manifest = write_manifest(DEFAULT_XML, DEFAULT_MODEL, DEFAULT_MANIFEST)
    config = load_config(args.config)
    receipt = latest_receipt(args.receipts)
    dirty = porcelain()

    print("package status")
    print(f"  route            {config.get('route')}")
    print(f"  version          {manifest['version']}")
    print(f"  commit           {manifest['sourceCommit']}")
    print(f"  sourceHash       {manifest['sourceHash']}")
    print(f"  artifactSha256   {manifest['artifactSha256']}")
    print(f"  assetId          {config.get('assetId') if config.get('assetId') else '(unset — owner checkpoint)'}")
    print(f"  creator          {config.get('creator')}")
    print(f"  working tree     {'DIRTY' if dirty else 'clean'}")
    if dirty:
        for line in dirty.splitlines()[:10]:
            print(f"                   {line.strip()}")

    if receipt is None:
        print("  last receipt     (none — nothing has ever been published)")
        print("  drift            n/a")
    else:
        drift = receipt.get("sourceHash") != manifest["sourceHash"]
        print(f"  last receipt     {receipt.get('version')} @ {receipt.get('sourceCommit', '')[:7]} "
              f"({receipt.get('publishedAt')})")
        print(f"  drift            {'YES — source has changed since the last publish' if drift else 'no'}")
        last, current = semver(receipt.get("version")), semver(manifest["version"])
        if last and current:
            if current > last:
                print(f"  semver           advanced {receipt.get('version')} -> {manifest['version']}")
            elif current == last:
                same = receipt.get("sourceHash") == manifest["sourceHash"]
                print(f"  semver           NOT advanced (still {manifest['version']}, "
                      f"{'same source' if same else 'DIFFERENT SOURCE — republishing this version is refused'})")
            else:
                print(f"  semver           BEHIND the last receipt ({receipt.get('version')})")
        studio = receipt.get("studio_verification") or {}
        print(f"  studio check     {studio.get('status')}"
              + (f" by {studio.get('by')} on {studio.get('date')}" if studio.get("status") == "verified" else ""))

    changelog = os.path.join(REPO, "CHANGELOG.md")
    if os.path.isfile(changelog):
        with open(changelog) as handle:
            mentioned = manifest["version"] in handle.read()
        print(f"  changelog        {'mentions' if mentioned else 'DOES NOT mention'} {manifest['version']}")
    else:
        print("  changelog        (CHANGELOG.md not present yet)")

    gate = read_gate_evidence()
    identity = gate_identity(manifest["version"], head_commit(), manifest["sourceHash"])
    print(f"  release identity {identity}")
    if gate is None:
        print(f"  gate evidence    absent ({shown(GATE_EVIDENCE)})")
    else:
        match = "matches" if gate.get("identity") == identity else "IS FOR A DIFFERENT IDENTITY"
        print(f"  gate evidence    status {gate.get('status')}, identity {match}")
    return 0


def cmd_verify(args):
    print("package verify")
    failures = []

    build_model(quiet=True)
    manifest = write_manifest(DEFAULT_XML, DEFAULT_MODEL, DEFAULT_MANIFEST)
    print(f"  [ ok ] build: {manifest['instanceCount']} instances, {manifest['moduleCount']} modules")

    problems, counts = inspect_tree(manifest)
    if problems:
        failures.append("tree inspection")
        print(f"  [FAIL] tree inspection: {len(problems)} problem(s)")
        for problem in problems:
            print(f"         - {problem}")
    else:
        print(
            f"  [ ok ] tree inspection: {counts['modules']} modules and {counts['folders']} folders present, "
            f"nothing else"
        )

    staged = stage(quiet=True)  # a fresh temp dir: this only wants the placeholder report
    if staged["placeholders"]:
        print(f"  [warn] distribution notices: placeholder text for {', '.join(staged['placeholders'])}")
    else:
        print("  [ ok ] distribution notices: LICENSE and THIRD_PARTY_NOTICES copied from the root files")

    purity = run([sys.executable, PURITY])
    if purity.returncode == 0:
        print("  [ ok ] library purity")
    else:
        failures.append("library purity")
        print("  [FAIL] library purity")
        for line in (purity.stdout + purity.stderr).strip().splitlines():
            print(f"         {line}")

    if args.skip_canary:
        print("  [skip] packaged-consumer canary (--skip-canary)")
    else:
        canary = run(["lune", "run", CANARY])
        for line in (canary.stdout + canary.stderr).strip().splitlines():
            print(f"         {line}")
        if canary.returncode == 0:
            print("  [ ok ] packaged-consumer canary")
        else:
            failures.append("packaged-consumer canary")
            print("  [FAIL] packaged-consumer canary")

    print("")
    if failures:
        print(f"package verify: FAIL ({', '.join(failures)})")
        return 1
    print("package verify: PASS")
    return 0


def _release_preamble(op, args, transport, decider=decide):
    config = load_config(args.config)
    route = args.route or config.get("route") or "studio"
    if route not in ("studio", "open-cloud"):
        print(f"package {op}: unknown route {route!r} (expected 'studio' or 'open-cloud')")
        raise SystemExit(1)
    api_key = api_key_from_env()
    facts = gather_facts(op, args, config, args.receipts, transport=transport if api_key else None, api_key=api_key)
    refusals = decider(facts)
    print(f"package {op} (route {route}, {'CONFIRMED' if args.confirm else 'DRY RUN'})")
    print(f"  version {facts['source_version']}  commit {facts['head_commit'][:7]}  "
          f"sourceHash {facts['source_hash'][:12]}  identity {facts['current_identity'][:12]}")
    return config, route, api_key, facts, refusals


def studio_publisher_steps(config, verb):
    build_model(publisher=True, quiet=True)
    print("")
    print("STUDIO ROUTE — do these steps by hand, then come back")
    print(f"  1. Open {shown(PUBLISHER_PLACE)} in Roblox Studio.")
    print("  2. In Explorer, select ReplicatedStorage > Facet.")
    if verb == "create":
        print("  3. Right-click it and choose 'Convert to Package'.")
        print(f"     Name:        {config.get('displayName')}")
        print(f"     Description: {config.get('description')}")
        print("     Ownership:   the account named in package/facet-package.json's creator.")
        print("                  Ownership transfers are NOT supported by the asset system — choose once.")
        print("  4. Copy the asset id from the new PackageLink's PackageId.")
        print("  5. Re-run: tools/package.sh create --confirm --version <v> --commit <sha> --asset-id <id>")
    else:
        print("  3. Right-click it and choose 'Publish to Package'.")
        print("  4. Add a version description naming the version and commit above.")
        print("  5. Leave this command running; it polls the asset's version list for the new version.")


def cmd_create(args, transport=None, decider=decide):
    transport = transport or HttpTransport()
    config, route, api_key, facts, refusals = _release_preamble("create", args, transport, decider)
    print_verdicts(facts, refusals)

    request_json = {
        "assetType": ASSET_TYPE,
        "displayName": config.get("displayName"),
        "description": config.get("description"),
        "creationContext": creation_context(config),
    }

    if route == "open-cloud":
        describe_request("POST", "/v1/assets", request_json, DEFAULT_MODEL)
    else:
        print("")
        print("REQUEST THAT WOULD BE SENT")
        print("  none on create — the studio route mints the asset in Studio and this command only READS it back:")
        print(f"  GET {API_BASE}/v1/assets/<the id you supply with --asset-id>")
        print("  headers: x-api-key: <redacted — never printed>")

    if not args.confirm:
        print("")
        print("DRY RUN — no network call was made. Re-run with --confirm once every guard is green.")
        return 0

    if refusals:
        print("")
        print(f"REFUSED — {len(refusals)} guard(s) failed; nothing was sent.")
        return 1

    if route == "studio":
        if not args.asset_id:
            studio_publisher_steps(config, "create")
            print("")
            print("No --asset-id given, so nothing was recorded. Do the steps above and re-run with --asset-id.")
            return 0
        status, payload = _api(transport, "GET", f"/v1/assets/{args.asset_id}", api_key)
        if status != 200:
            print(f"  read-back failed: HTTP {status} {json.dumps(payload)[:300]}")
            return 1
        creator = (payload.get("creationContext") or {}).get("creator") or {}
        configured = config.get("creator") or {}
        key = "userId" if configured.get("type") == "user" else "groupId"
        if str(creator.get(key)) != str(configured.get("id")):
            print(f"  read-back refuses the id: asset {args.asset_id} belongs to {creator}, not {configured}")
            return 1
        if payload.get("assetType") and ASSET_TYPE.lower() not in str(payload["assetType"]).lower():
            print(f"  read-back refuses the id: asset {args.asset_id} is a {payload['assetType']}, not a Model")
            return 1
        config["assetId"] = int(args.asset_id)
        save_config(args.config, config)
        print(f"  recorded assetId {args.asset_id} in {shown(args.config)}")
        return 0

    body, content_type = multipart(
        {"request": json.dumps(request_json)},
        {"fileContent": (os.path.basename(DEFAULT_MODEL), RBXM_CONTENT_TYPE, read_bytes(DEFAULT_MODEL))},
    )
    status, payload = _api(transport, "POST", "/v1/assets", api_key, body=body, content_type=content_type)
    if status != 200:
        print(f"  create failed: HTTP {status} {json.dumps(payload)[:300]}")
        return 1
    operation_path = payload.get("path")
    status, payload = poll_operation(transport, operation_path, api_key)
    if status != 200 or not payload.get("done") or payload.get("error"):
        print(f"  operation did not complete: HTTP {status} {json.dumps(payload)[:300]}")
        return 1
    asset = payload.get("response") or {}
    config["assetId"] = int(asset.get("assetId"))
    save_config(args.config, config)
    print(f"  created assetId {config['assetId']} (revision {asset.get('revisionId')})")
    path, receipt_body = write_receipt(
        args.receipts,
        config,
        facts,
        operation_path=operation_path,
        asset_revision={
            "revisionId": asset.get("revisionId"),
            "revisionCreateTime": asset.get("revisionCreateTime"),
        },
        moderation=(asset.get("moderationResult") or {}).get("moderationState"),
        actor=args.actor or os.environ.get("USER"),
        gate=facts.get("gate"),
    )
    record_version(args.config, config, receipt_body)
    print(f"  receipt {shown(path)}")
    return 0


def cmd_publish(args, transport=None, decider=decide):
    transport = transport or HttpTransport()
    config, route, api_key, facts, refusals = _release_preamble("publish", args, transport, decider)
    print_verdicts(facts, refusals)

    asset_id = config.get("assetId") or "<assetId — unset until create>"
    request_json = {
        "assetId": str(asset_id),
        "assetType": ASSET_TYPE,
        "displayName": config.get("displayName"),
        "description": config.get("description"),
    }

    if route == "open-cloud":
        describe_request("PATCH", f"/v1/assets/{asset_id}", request_json, DEFAULT_MODEL)
        print("  NOTE: the usage guide says content updates currently work for .fbx only. This route is")
        print("        implemented in full and unproved for .rbxm until the Studio spike says otherwise.")
    else:
        print("")
        print("REQUEST THAT WOULD BE SENT")
        print("  none on publish — the studio route publishes in Studio and this command only READS:")
        print(f"  GET {API_BASE}/v1/assets/{asset_id}/versions?maxPageSize=1")
        print("  headers: x-api-key: <redacted — never printed>")

    if not args.confirm:
        print("")
        print("DRY RUN — no network call was made. Re-run with --confirm once every guard is green.")
        return 0

    if refusals:
        print("")
        print(f"REFUSED — {len(refusals)} guard(s) failed; nothing was sent.")
        return 1

    receipt = facts.get("latest_receipt") or {}
    known_revision = (receipt.get("assetRevision") or {}).get("revisionId")

    if route == "studio":
        studio_publisher_steps(config, "publish")
        print("")
        print(f"  polling {API_BASE}/v1/assets/{asset_id}/versions for a version newer than {known_revision!r}")
        deadline = time.time() + args.timeout
        found = None
        while time.time() < deadline:
            status, payload = _api(transport, "GET", f"/v1/assets/{asset_id}/versions?maxPageSize=1", api_key)
            if status == 200:
                versions = payload.get("assetVersions") or payload.get("data") or []
                if versions:
                    newest = versions[0]
                    number = str(newest.get("path", "")).rsplit("/", 1)[-1]
                    if known_revision is None or str(number) != str(known_revision):
                        found = newest
                        break
            time.sleep(min(args.poll, 60))
        if found is None:
            print(f"  no new version appeared within {args.timeout}s; nothing was recorded")
            return 1
        number = str(found.get("path", "")).rsplit("/", 1)[-1]
        moderation = (found.get("moderationResult") or {}).get("moderationState")
        print(f"  observed version {number} (moderation {moderation})")
        path, receipt_body = write_receipt(
            args.receipts,
            config,
            facts,
            operation_path=None,
            asset_revision={"revisionId": number, "revisionPath": found.get("path")},
            moderation=moderation,
            actor=args.actor or os.environ.get("USER"),
            gate=facts.get("gate"),
        )
        record_version(args.config, config, receipt_body)
        print(f"  receipt {shown(path)}")
        return 0

    body, content_type = multipart(
        {"request": json.dumps(request_json)},
        {"fileContent": (os.path.basename(DEFAULT_MODEL), RBXM_CONTENT_TYPE, read_bytes(DEFAULT_MODEL))},
    )
    status, payload = _api(transport, "PATCH", f"/v1/assets/{asset_id}", api_key, body=body, content_type=content_type)
    if status != 200:
        print(f"  publish failed: HTTP {status} {json.dumps(payload)[:300]}")
        return 1
    operation_path = payload.get("path")
    status, payload = poll_operation(transport, operation_path, api_key)
    if status != 200 or not payload.get("done") or payload.get("error"):
        print(f"  operation did not complete: HTTP {status} {json.dumps(payload)[:300]}")
        return 1
    asset = payload.get("response") or {}
    moderation = (asset.get("moderationResult") or {}).get("moderationState")
    print(f"  published revision {asset.get('revisionId')} (moderation {moderation})")
    if moderation is not None and moderation not in APPROVED_MODERATION:
        print(f"  WARNING: moderation is {moderation!r}; the receipt records it and `status` will keep saying so")
    path, receipt_body = write_receipt(
        args.receipts,
        config,
        facts,
        operation_path=operation_path,
        asset_revision={
            "revisionId": asset.get("revisionId"),
            "revisionCreateTime": asset.get("revisionCreateTime"),
        },
        moderation=moderation,
        actor=args.actor or os.environ.get("USER"),
        gate=facts.get("gate"),
    )
    record_version(args.config, config, receipt_body)
    print(f"  receipt {shown(path)}")
    return 0


def cmd_rollback(args):
    """Prints; never uploads. Rolling back by re-uploading an old tree would mint
    a NEW revision whose contents are old — a version history that lies. Both
    real mechanisms select an EXISTING version instead."""
    config = load_config(args.config)
    asset_id = config.get("assetId") or "<assetId — unset until create>"
    receipt = latest_receipt(args.receipts)
    print("package rollback — this command never uploads anything.")
    print("")
    print("ROUTE A — Studio package version history (the documented Package mechanism)")
    print("  1. In Studio, right-click the package > Package Options > Package Details.")
    print("  2. Open the Versions tab: every published version with its date and description.")
    print("  3. Click the checkmark beside the version to restore, then Submit.")
    print("  4. Note: restoring does NOT reset package attributes; revert those separately.")
    print("  5. Consumers on AutoUpdate pick the restored version up on next place-open;")
    print("     a locally modified copy has AutoUpdate disabled and is skipped, not overwritten.")
    print("")
    print("ROUTE B — Open Cloud asset-version rollback (the scripted mechanism)")
    print("  POST " + API_BASE + f"/v1/assets/{asset_id}/versions:rollback")
    print("  headers: x-api-key: <redacted — never printed>")
    print("  body: multipart/form-data")
    print(f"    part 'assetVersion': assets/{asset_id}/versions/<versionNumber>")
    print("  Scopes: asset:read AND asset:write. Rate limit 100/min.")
    print("  List the versions first: GET " + API_BASE + f"/v1/assets/{asset_id}/versions?maxPageSize=50")
    print("")
    print("WHICH ONE. The two sequences are not proved to be the same sequence — the docs")
    print("never reconcile Package versions with Asset revisions. Until the Studio spike")
    print("answers that, roll back on the SAME route the version was published on.")
    if receipt:
        print("")
        print(f"  newest receipt: {receipt.get('version')} route {receipt.get('route')} "
              f"revision {(receipt.get('assetRevision') or {}).get('revisionId')}")
    return 0


def cmd_stamp(args):
    with open(args.receipt) as handle:
        receipt = json.load(handle)
    if not args.studio_verified:
        print("package stamp: pass --studio-verified to record a completed Studio check")
        return 1
    receipt["studio_verification"] = {
        "status": "verified",
        "by": args.by,
        "date": now_iso(),
        "notes": args.notes,
    }
    with open(args.receipt, "w") as handle:
        json.dump(receipt, handle, indent=2)
        handle.write("\n")
    print(f"stamped {shown(args.receipt)}: verified by {args.by}")
    return 0


def cmd_identity(args):
    print(gate_identity(read_version(), head_commit(), source_hash()))
    return 0


# ── selftest ─────────────────────────────────────────────────────────────────


def good_facts(op):
    """An all-green fact set. Every refusal test below mutates exactly ONE key of
    this, so a refusal that fires for a second reason is a failed test rather than
    a passing one."""
    identity = "i" * 64
    base = {
        "op": op,
        "api_key_present": True,
        "git_dirty": False,
        "arg_commit": "c" * 40,
        "head_commit": "c" * 40,
        "arg_version": "0.11.0",
        "source_version": "0.11.0",
        "source_hash": "s" * 64,
        "fresh_build_hash": "b" * 64,
        "manifest_hash": "b" * 64,
        "config_creator": {"type": "user", "id": 1234},
        "arg_creator_type": "user",
        "arg_creator_id": 1234,
        "config_asset_id": None,
        "arg_asset_id": None,
        "gate": {"schema": GATE_SCHEMA, "status": "PASS", "identity": identity},
        "current_identity": identity,
        "latest_receipt": None,
        "cloud_revision": None,
        "moderation": None,
    }
    if op == "publish":
        base["config_asset_id"] = 999
        base["arg_asset_id"] = 999
        base["latest_receipt"] = {
            "version": "0.10.0",
            "sourceHash": "old" + "0" * 61,
            "operationPath": "operations/op-1",
            "assetRevision": {"revisionId": "3"},
        }
        base["cloud_revision"] = {"revisionId": "3"}
        base["moderation"] = "Approved"
    return base


def mutate(op, **changes):
    facts = good_facts(op)
    facts.update(changes)
    return facts


REFUSAL_CASES = [
    ("api-key-missing", "create", {"api_key_present": False}),
    ("dirty-tree", "create", {"git_dirty": True}),
    ("commit-mismatch", "create", {"arg_commit": None}),
    ("commit-mismatch", "create", {"arg_commit": "d" * 40}),
    ("version-mismatch", "create", {"arg_version": None}),
    ("version-mismatch", "create", {"arg_version": "9.9.9"}),
    ("build-drift", "create", {"fresh_build_hash": "x" * 64}),
    ("creator-unset", "create", {"config_creator": {"type": None, "id": None}, "arg_creator_type": None, "arg_creator_id": None}),
    ("creator-mismatch", "create", {"arg_creator_id": 4321}),
    ("creator-mismatch", "create", {"arg_creator_type": "group"}),
    ("asset-id-present", "create", {"config_asset_id": 777}),
    ("asset-id-missing", "publish", {"config_asset_id": None, "arg_asset_id": None, "cloud_revision": None}),
    ("asset-id-mismatch", "publish", {"arg_asset_id": 555}),
    ("gate-evidence-missing", "create", {"gate": None}),
    ("gate-evidence-failed", "create", {"gate": {"status": "FAIL", "identity": "i" * 64}}),
    ("gate-identity-mismatch", "create", {"gate": {"status": "PASS", "identity": "z" * 64}}),
    (
        "operation-in-flight",
        "publish",
        {
            "latest_receipt": {
                "version": "0.10.0",
                "sourceHash": "old" + "0" * 61,
                "operationPath": "operations/stuck",
                "assetRevision": None,
            },
            "cloud_revision": None,
        },
    ),
    ("cloud-revision-newer", "publish", {"cloud_revision": {"revisionId": "4"}}),
    (
        "version-not-advanced",
        "publish",
        {
            "latest_receipt": {
                "version": "0.11.0",
                "sourceHash": "s" * 64,
                "operationPath": "operations/op-1",
                "assetRevision": {"revisionId": "3"},
            }
        },
    ),
    (
        "version-hash-conflict",
        "publish",
        {
            "latest_receipt": {
                "version": "0.11.0",
                "sourceHash": "different" + "0" * 55,
                "operationPath": "operations/op-1",
                "assetRevision": {"revisionId": "3"},
            }
        },
    ),
    ("moderation-not-approved", "publish", {"moderation": "Rejected"}),
]


class _Args:
    def __init__(self, **kwargs):
        for key, value in kwargs.items():
            setattr(self, key, value)


def selftest():
    ok = True
    print("package --selftest")

    for op in ("create", "publish"):
        refusals = decide(good_facts(op))
        if refusals:
            ok = False
            print(f"  [WRONG] the all-good {op} facts produced {[r.code for r in refusals]}")
        else:
            print(f"  [ ok  ] the all-good {op} facts produce no refusal")

    for expected, op, change in REFUSAL_CASES:
        refusals = decide(mutate(op, **change))
        codes = [refusal.code for refusal in refusals]
        if codes == [expected]:
            print(f"  [BITES] {op}: {expected}")
        else:
            ok = False
            print(f"  [WRONG] {op}: expected exactly [{expected}], got {codes}")

    covered = {code for code, _, _ in REFUSAL_CASES}
    for code in (
        "api-key-missing",
        "dirty-tree",
        "commit-mismatch",
        "version-mismatch",
        "build-drift",
        "creator-unset",
        "creator-mismatch",
        "asset-id-present",
        "asset-id-missing",
        "asset-id-mismatch",
        "gate-evidence-missing",
        "gate-evidence-failed",
        "gate-identity-mismatch",
        "operation-in-flight",
        "cloud-revision-newer",
        "version-not-advanced",
        "version-hash-conflict",
        "moderation-not-approved",
    ):
        if code not in covered:
            ok = False
            print(f"  [WRONG] no case exercises {code}")

    ok = _selftest_transport() and ok
    print("")
    print("package --selftest: " + ("PASS" if ok else "FAIL"))
    return ok


CREATED_ASSET = {
    "path": "assets/424242",
    "assetId": "424242",
    "revisionId": "1",
    "revisionCreateTime": "2026-08-30T00:00:00Z",
    # proto-style spellings on purpose: the usage guide's worked example returns
    # `ASSET_TYPE_DECAL` / `MODERATION_STATE_APPROVED` while the schema table says
    # `Model` / `Approved`, and the docs never reconcile them (research note
    # §1.6). The fake serves the shape that would break a naive equality check.
    "assetType": "ASSET_TYPE_MODEL",
    "creationContext": {"creator": {"userId": "1234"}},
    "moderationResult": {"moderationState": "MODERATION_STATE_APPROVED"},
}


def _selftest_transport():
    """create and publish end to end against the fake, on a TEMP copy of the
    config and a TEMP receipts directory. The real `package/facet-package.json`
    is never opened for writing here — a selftest that mints an asset id into the
    tracked config would be a selftest that publishes.

    TWO PASSES, and the first is the important one. Pass A runs `create --confirm`
    with the REAL guards against whatever state this working tree is in and
    asserts the transport was never touched: that is the proof that guards run
    BEFORE the call, not beside it. Pass B substitutes a decider that returns no
    refusal — the same injection seam as the transport — so the request/poll/
    record path can be driven on a tree that is, as any working tree is, dirty."""
    ok = True
    work = tempfile.mkdtemp(prefix="facet-package-selftest-")
    global GATE_EVIDENCE
    real_gate, real_key = GATE_EVIDENCE, os.environ.get("ROBLOX_API_KEY")
    try:
        version, commit = read_version(), head_commit()
        gate_path = os.path.join(work, "latest-release.json")
        with open(gate_path, "w") as handle:
            json.dump(
                {
                    "schema": GATE_SCHEMA,
                    "tier": "release",
                    "status": "PASS",
                    "identity": gate_identity(version, commit, source_hash()),
                },
                handle,
            )
        GATE_EVIDENCE = gate_path
        os.environ["ROBLOX_API_KEY"] = "selftest-key-never-sent"

        def base_config(asset_id):
            config = load_config(DEFAULT_CONFIG)
            config["route"] = "open-cloud"
            config["creator"] = {"type": "user", "id": 1234}
            config["assetId"] = asset_id
            return config

        def args_for(config_path, receipts_dir):
            return _Args(
                config=config_path,
                receipts=receipts_dir,
                route="open-cloud",
                confirm=True,
                version=version,
                commit=commit,
                asset_id=None,
                creator_id=None,
                creator_type=None,
                actor="selftest",
                timeout=1,
                poll=1,
            )

        no_refusals = lambda facts: []  # noqa: E731 — the injected decider, one expression

        # ── pass A: the real guards, and nothing must reach the transport ────
        guard_config = os.path.join(work, "guarded.json")
        save_config(guard_config, base_config(None))
        silent = FakeTransport([])
        code = cmd_create(args_for(guard_config, os.path.join(work, "guarded-receipts")), transport=silent)
        if code == 1 and not silent.calls:
            print("  [ ok  ] create --confirm under the real guards: refused, zero transport calls")
        elif code == 0 and not silent.calls:
            # a clean tree with real gate evidence would legitimately pass; then
            # the fake has no canned POST and would have raised, so this branch
            # means the request path was never reached at all
            ok = False
            print("  [WRONG] create --confirm returned 0 without calling the transport")
        else:
            ok = False
            print(f"  [WRONG] create --confirm exit {code} with calls {silent.calls}")

        # ── pass B: the request/poll/record path ─────────────────────────────
        print("  ---- pass B: guards stubbed out (proven above); driving the request path ----")
        create_config = os.path.join(work, "create.json")
        create_receipts = os.path.join(work, "create-receipts")
        save_config(create_config, base_config(None))
        create_transport = FakeTransport(
            [
                ("POST", "/v1/assets", 200, {"path": "operations/op-create", "done": False}),
                ("GET", "/v1/operations/op-create", 200, {"path": "operations/op-create", "done": False}),
                ("GET", "/v1/operations/op-create", 200,
                 {"path": "operations/op-create", "done": True, "response": CREATED_ASSET}),
            ]
        )
        code = cmd_create(args_for(create_config, create_receipts), transport=create_transport, decider=no_refusals)
        recorded = load_config(create_config).get("assetId")
        polls = sum(1 for call in create_transport.calls if "/operations/" in call["url"])
        if code == 0 and recorded == 424242 and polls == 2:
            print("  [ ok  ] create against the fake: POST -> operation pending -> done, assetId 424242 recorded")
        else:
            ok = False
            print(f"  [WRONG] create against the fake: exit {code}, assetId {recorded}, {polls} operation polls")
        recorded_versions = load_config(create_config).get("versions") or []
        if len(recorded_versions) == 1 and recorded_versions[0]["version"] == version:
            print(f"  [ ok  ] the config's versions list gained one entry for {version}")
        else:
            ok = False
            print(f"  [WRONG] versions list reads {recorded_versions}")

        real = load_config(DEFAULT_CONFIG)
        if real.get("assetId") is not None or real.get("versions"):
            ok = False
            print("  [WRONG] the selftest wrote into the real package/facet-package.json")
        else:
            print("  [ ok  ] the real package/facet-package.json still records no assetId and no versions")

        publish_config = os.path.join(work, "publish.json")
        publish_receipts = os.path.join(work, "publish-receipts")
        save_config(publish_config, base_config(424242))
        os.makedirs(publish_receipts)
        with open(os.path.join(publish_receipts, "0.9.0-0000000.json"), "w") as handle:
            json.dump(
                {
                    "schema": RECEIPT_SCHEMA,
                    "version": "0.9.0",
                    "sourceHash": "old" + "0" * 61,
                    "operationPath": "operations/op-old",
                    "assetRevision": {"revisionId": "1"},
                    "publishedAt": "2026-08-01T00:00:00Z",
                },
                handle,
            )
        published = dict(CREATED_ASSET, revisionId="2", revisionCreateTime="2026-08-30T01:00:00Z")
        publish_transport = FakeTransport(
            [
                ("GET", "/v1/assets/424242", 200, CREATED_ASSET),
                ("PATCH", "/v1/assets/424242", 200, {"path": "operations/op-publish", "done": False}),
                ("GET", "/v1/operations/op-publish", 200,
                 {"path": "operations/op-publish", "done": True, "response": published}),
            ]
        )
        code = cmd_publish(args_for(publish_config, publish_receipts), transport=publish_transport, decider=no_refusals)
        written = [pair for pair in receipts(publish_receipts) if pair[1].get("version") == version]
        if code == 0 and written and written[-1][1]["assetRevision"]["revisionId"] == "2":
            print(f"  [ ok  ] publish against the fake: receipt {os.path.basename(written[-1][0])} at revision 2")
        else:
            ok = False
            print(f"  [WRONG] publish against the fake: exit {code}, receipts {[p for p, _ in written]}")
        if written:
            with open(written[-1][0]) as handle:
                body = handle.read()
            if "selftest-key-never-sent" in body:
                ok = False
                print("  [WRONG] the API key reached a receipt")
            else:
                print("  [ ok  ] no API key anywhere in the receipt")
    finally:
        GATE_EVIDENCE = real_gate
        if real_key is None:
            os.environ.pop("ROBLOX_API_KEY", None)
        else:
            os.environ["ROBLOX_API_KEY"] = real_key
        shutil.rmtree(work, ignore_errors=True)
    return ok


# ── CLI ──────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(prog="package.py", description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true", help="prove every refusal and drive the fake transport")
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--receipts", default=DEFAULT_RECEIPTS)
    sub = parser.add_subparsers(dest="command")

    stage_parser = sub.add_parser("stage", help="regenerate build/.stage/Distribution (called by build_model.sh)")
    stage_parser.add_argument(
        "--out", default=None, help="staging directory (build_model.sh passes a per-invocation one)"
    )
    stage_parser.add_argument("--quiet", action="store_true")
    stage_parser.set_defaults(func=cmd_stage)

    manifest_parser = sub.add_parser("manifest", help="write the semantic manifest (called by build_model.sh)")
    manifest_parser.add_argument("--model", required=True, help="the .rbxmx twin to walk")
    manifest_parser.add_argument("--artifact", required=True, help="the artifact whose sha256 is recorded")
    manifest_parser.add_argument("--out", required=True)
    manifest_parser.set_defaults(func=cmd_manifest)

    build_parser = sub.add_parser("build", help="rebuild the model and its manifest")
    build_parser.add_argument("--publisher", action="store_true", help="also build build/FacetPublisher.rbxl")
    build_parser.set_defaults(func=cmd_build)

    sub.add_parser("status", help="this tree against the last receipt").set_defaults(func=cmd_status)

    verify_parser = sub.add_parser("verify", help="build + tree inspection + purity + the packaged canary")
    verify_parser.add_argument("--skip-canary", action="store_true")
    verify_parser.set_defaults(func=cmd_verify)

    for name, func in (("create", cmd_create), ("publish", cmd_publish)):
        release_parser = sub.add_parser(name, help=f"{name} the Package asset (DRY RUN unless --confirm)")
        release_parser.add_argument("--confirm", action="store_true", help="actually make the call")
        release_parser.add_argument("--route", choices=("studio", "open-cloud"))
        release_parser.add_argument("--version")
        release_parser.add_argument("--commit")
        release_parser.add_argument("--asset-id")
        release_parser.add_argument("--creator-id")
        release_parser.add_argument("--creator-type", choices=("user", "group"))
        release_parser.add_argument("--actor")
        release_parser.add_argument("--timeout", type=int, default=1800, help="studio-route version poll timeout (s)")
        release_parser.add_argument("--poll", type=int, default=15, help="studio-route poll interval (s)")
        release_parser.set_defaults(func=func)

    sub.add_parser("rollback", help="print both rollback procedures; never uploads").set_defaults(func=cmd_rollback)

    stamp_parser = sub.add_parser("stamp", help="record a human's Studio verification on a receipt")
    stamp_parser.add_argument("--receipt", required=True)
    stamp_parser.add_argument("--studio-verified", action="store_true")
    stamp_parser.add_argument("--by")
    stamp_parser.add_argument("--notes")
    stamp_parser.set_defaults(func=cmd_stamp)

    sub.add_parser("identity", help="print this release's gate identity").set_defaults(func=cmd_identity)

    args = parser.parse_args()
    if args.selftest:
        raise SystemExit(0 if selftest() else 1)
    if not getattr(args, "func", None):
        parser.print_help()
        raise SystemExit(2)
    raise SystemExit(args.func(args))


if __name__ == "__main__":
    main()
