#!/usr/bin/env python3
CLI_HELP = """Materialize the exact Compose pin. The snapshot is tracked, generated and read-only."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import posixpath
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "src/vendor/compose"
PIN = DEST / "UPSTREAM.lock"

DOCS_SOURCE = ".agents/skills/compose"
DOCS_DEST = ROOT / "skills/compose"






COMMIT = re.compile(r"\A[0-9a-f]{40}\Z")
REPOSITORY = re.compile(r"\Ahttps://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:\.git)?\Z")


def checked_pin(pin):

    commit = pin.get("commit")
    repository = pin.get("repository")
    if not isinstance(commit, str) or not COMMIT.match(commit):
        raise SystemExit(
            f"Compose: {PIN.relative_to(ROOT)} records commit {commit!r}, which is not a full "
            "40-character lowercase-hex object name. Refusing to pass it to git."
        )
    if not isinstance(repository, str) or not REPOSITORY.match(repository):
        raise SystemExit(
            f"Compose: {PIN.relative_to(ROOT)} records repository {repository!r}, which is not an "
            "https://github.com/<owner>/<name> URL. Refusing to fetch from it."
        )
    return repository, commit


def git(repository, *args):
    return subprocess.check_output(["git", "-C", str(repository), *args])


def safe_member_name(name):



    probe = name.replace("\\", "/")
    if probe.startswith("/") or ":" in probe.split("/")[0]:
        raise SystemExit(f"Compose: archive member {name!r} is an absolute path; refusing")
    if ".." in posixpath.normpath(probe).split("/"):
        raise SystemExit(f"Compose: archive member {name!r} escapes the snapshot root; refusing")
    return name


def materialize(repository, pin):
    _url, pinned = checked_pin(pin)

    commit = git(repository, "rev-parse", "--verify", "--end-of-options", pinned + "^{commit}")
    commit = commit.decode().strip()
    if commit != pinned:
        raise ValueError("Compose pin must be a full commit identity")
    archive = git(repository, "archive", commit, "--", "src/core", "src/roblox", "LICENSE", DOCS_SOURCE)
    files, docs = {}, {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        for entry in source:


            if not entry.isfile():
                continue
            name = safe_member_name(entry.name)
            data = source.extractfile(entry).read()
            if name.startswith(DOCS_SOURCE + "/"):
                docs[name.removeprefix(DOCS_SOURCE + "/")] = data
            else:
                files[name.removeprefix("src/")] = data
    files["license.luau"] = b"--!strict\nreturn [=[\n" + files["LICENSE"] + b"\n]=]\n"
    return files, docs


def verify(pin):
    for name, digest in pin["docs"].items():
        path = DOCS_DEST / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            return False
    present = {path.relative_to(DOCS_DEST).as_posix() for path in DOCS_DEST.rglob("*") if path.is_file()}
    if present != set(pin["docs"]):
        return False
    generated = {
        path.relative_to(DEST).as_posix()
        for path in DEST.rglob("*")
        if path.is_file() and path not in (PIN, DEST / "README.md")
    }
    if generated != set(pin["sha256"]):
        return False
    expected_dirs = {parent.as_posix() for name in generated
                     for parent in Path(name).parents if parent != Path(".")}
    actual_dirs = {path.relative_to(DEST).as_posix()
                   for path in DEST.rglob("*") if path.is_dir()}
    if actual_dirs != expected_dirs:
        return False
    for name, digest in pin["sha256"].items():
        path = DEST / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            return False
    return True


def fetch_repository(source, scratch, url, commit):

    if source is not None:
        return source
    repository = Path(scratch) / "repository"
    subprocess.run(["git", "init", "--quiet", "--", str(repository)], check=True)


    git(repository, "fetch", "--depth=1", "--", url, commit)
    return repository


def write_snapshot(files, docs):
    for path in list(DOCS_DEST.rglob("*")) if DOCS_DEST.exists() else []:
        if path.is_file():
            path.unlink()
    for name, data in docs.items():
        path = DOCS_DEST / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for path in DEST.rglob("*"):
        if (path.is_file() and path not in (PIN, DEST / "README.md")
                and path.relative_to(DEST).as_posix() not in files):
            path.unlink()
    for name, data in files.items():
        path = DEST / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


    for directory in sorted((p for p in DEST.rglob("*") if p.is_dir()),
                            key=lambda p: len(p.parts), reverse=True):
        if not any(directory.iterdir()):
            directory.rmdir()


def inventory(entries):
    return {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}


def bump(pin, commit, source):

    if not COMMIT.match(commit):
        raise SystemExit(f"Compose: --bump takes a full 40-character commit, not {commit!r}")
    previous = pin["commit"]
    before = dict(pin["sha256"])
    pin["commit"] = commit
    url, _ = checked_pin(pin)
    with tempfile.TemporaryDirectory(prefix="facet-compose-") as scratch:
        files, docs = materialize(fetch_repository(source, scratch, url, commit), pin)
    pin["sha256"], pin["docs"] = inventory(files), inventory(docs)
    write_snapshot(files, docs)
    PIN.write_text(json.dumps(pin, indent=2) + "\n")
    assert verify(pin), "Compose materialization did not match its pin"
    changed = sorted(n for n in set(before) | set(pin["sha256"]) if before.get(n) != pin["sha256"].get(n))
    print(f"Compose: bumped {previous[:12]} -> {commit[:12]}; {len(changed)} snapshot file(s) changed")
    for name in changed:
        print("  " + name)


    stale = []
    for path in (ROOT / "THIRD_PARTY_NOTICES.md", ROOT / "docs/reference/api.md", DEST / "README.md"):
        if path.is_file() and previous in path.read_text():
            stale.append(path.relative_to(ROOT).as_posix())
    if stale:
        print("Compose: these still name the previous commit: " + ", ".join(stale))
    print("Compose: re-record the provenance receipt, then run tools/verify.sh full")


def main():
    parser = argparse.ArgumentParser(description=CLI_HELP)
    parser.add_argument("--source", type=Path, help="local Git repository containing the pinned commit")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--bump", metavar="COMMIT", help="move the pin to this full commit and re-materialize")
    args = parser.parse_args()
    pin = json.loads(PIN.read_text())
    if args.bump is not None:
        if args.check:
            raise SystemExit("Compose: --bump and --check are different requests")
        return bump(pin, args.bump, args.source)
    url, commit = checked_pin(pin)
    if verify(pin):
        print("Compose: pinned dependency verified " + commit)
        return
    if args.check:
        raise SystemExit("Compose: missing or modified dependency; run python3 tools/sync_compose.py")
    with tempfile.TemporaryDirectory(prefix="facet-compose-") as scratch:
        files, docs = materialize(fetch_repository(args.source, scratch, url, commit), pin)
        if inventory(files) != pin["sha256"] or inventory(docs) != pin["docs"]:
            raise SystemExit("Compose: archive does not match pinned integrity inventory")
        write_snapshot(files, docs)
    assert verify(pin), "Compose materialization did not match its pin"
    print("Compose: materialized " + pin["commit"])


if __name__ == "__main__":
    main()
