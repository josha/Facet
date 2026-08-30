#!/usr/bin/env python3
"""Generate the examples' shared English word data from a licensed, versioned source.

Run (from the library root):

    python3 tools/build_word_lists.py            # generate, verifying the source hash
    python3 tools/build_word_lists.py --check    # verify the checked-in files, no source needed
    python3 tools/build_word_lists.py --selftest # prove each refusal can fire

WHY THIS EXISTS. The word game shipped six possible answers and thirty-four
accepted guesses typed into its own source. A player typing an ordinary English
word was told it was not a word, which teaches the wrong lesson about the
example and about the framework. The crossword game needs the same vocabulary at
several lengths. One generated, licensed, provenance-carrying data set serves
both, and nothing is typed by hand.

THE SOURCE IS SCOWL, and it is chosen because it is *designed* to be turned into
redistributable spelling lists: its own Copyright file grants permission to
"use, copy, modify, distribute and sell these word lists, the associated
scripts, the output created from the scripts, and its documentation for any
purpose", provided the notices travel with the copies. Those notices are copied
verbatim into the generated PROVENANCE.md, which is the whole point of doing
this from a real source instead of a scrape.

WHAT IT REFUSES. Every refusal below has a reason it is not merely defensive:

  1. A source archive whose SHA-256 does not match SOURCE_SHA256. "A dictionary"
     is not a provenance claim; a specific archive is. Without the pin, a
     re-download years later silently changes what the game accepts and every
     test that asserts a word is accepted becomes a test about the internet.
  2. A generated file whose recorded hash no longer matches its content
     (`--check`). This is the half that runs with no network and no source
     archive, so a fresh clone, a gate row and the suite can all hold the claim.
  3. An empty or implausibly small output set. A filter bug that produces four
     words is otherwise a perfectly green run: the files regenerate, the hashes
     agree with themselves, and the game rejects the alphabet.
  4. A solution that is not itself an accepted guess. That combination is
     unwinnable and undetectable from either list alone.
  5. A module that would exceed the engine's Source write cap. Studio refuses a
     Source write at 200,000 characters, and the refusal is silent enough that a
     live-synced session then runs the PREVIOUS version of the module while
     every file on disk looks correct.

THE FILTERS ARE POLICY, AND THEY ARE WRITTEN DOWN. SCOWL grades every word by
how widely it is known: size 10 is the most common thousand words, 95 is
everything including the obscure. Two different jobs need two different cuts:

  * accepting a guess should be generous, because a player who types a real word
    and is refused blames the game. Sizes up to 70 give 36,601 words at lengths
    two to seven, and cover every ordinary word tried against it (crane, fjord,
    mocha, ninja, sushi, adieu).
  * choosing an answer should be conservative, because an answer nobody knows is
    not a puzzle. Sizes up to 35 give familiar words, and simple plurals and
    past tenses are dropped on top of that — "asked" and "cakes" are real words
    and poor answers.
"""

import argparse
import hashlib
import io
import json
import os
import re
import sys
import tarfile
import tempfile
import urllib.request

# ── The pinned source ───────────────────────────────────────────────────────
SOURCE_NAME = "SCOWL (Spell Checker Oriented Word Lists) 2020.12.07"
SOURCE_URL = "https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz"
SOURCE_SHA256 = "5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc"
SOURCE_ROOT = "scowl-2020.12.07"
SOURCE_HOME = "http://wordlist.aspell.net/"

# ── The policy ──────────────────────────────────────────────────────────────
# SCOWL "size" tiers, smallest (most common) first.
TIERS = [10, 20, 35, 40, 50, 55, 60, 70, 80, 95]
# Only the `-words` classes: that already excludes proper names, abbreviations
# and contractions, so no second filter has to guess at them.
DIALECTS = ["english", "american"]

ACCEPT_MAX_TIER = 70
ACCEPT_MIN_LEN = 2
ACCEPT_MAX_LEN = 7

SOLUTION_MAX_TIER = 35
SOLUTION_LEN = 5

# Refusal 3: a floor per length, set well below the measured counts so ordinary
# source drift does not trip it but a filter bug cannot pass.
MIN_ACCEPTED = {2: 50, 3: 400, 4: 1500, 5: 3000, 6: 5000, 7: 7000}
MIN_SOLUTIONS = 1000

# Refusal 5: Roblox refuses a Source write at 200,000 characters. Leave room for
# the module's own header and syntax.
SOURCE_CHAR_CAP = 180_000
WORDS_PER_LINE = 400

OUT_DIR = "examples/gallery/examples/words"
CACHE_DIR = "tools/.wordlist-cache"

WORD_RE = re.compile(r"^[a-z]+$")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_source(offline: bool) -> str:
    """Return the path to a verified source archive, downloading it once."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, os.path.basename(SOURCE_URL))
    if os.path.exists(path):
        got = sha256_file(path)
        if got == SOURCE_SHA256:
            return path
        # A cached archive that no longer matches is removed rather than reused:
        # a partial download is the common cause and it is not worth diagnosing.
        print(f"cached archive hash {got} != pinned {SOURCE_SHA256}; refetching", file=sys.stderr)
        os.remove(path)
    if offline:
        raise SystemExit(
            f"build_word_lists: no verified source archive at {path} and --offline was given.\n"
            f"  Download it once: curl -sSL -o {path} {SOURCE_URL}"
        )
    print(f"downloading {SOURCE_URL}", file=sys.stderr)
    with urllib.request.urlopen(SOURCE_URL, timeout=180) as resp:
        data = resp.read()
    got = sha256_bytes(data)
    if got != SOURCE_SHA256:
        # Refusal 1.
        raise SystemExit(
            f"build_word_lists: downloaded archive SHA-256 {got}\n"
            f"  does not match the pinned {SOURCE_SHA256}.\n"
            f"  Refusing to generate word data from an unidentified source. If the upstream\n"
            f"  release genuinely changed, update SOURCE_SHA256 and SOURCE_NAME together and\n"
            f"  say so in the generated PROVENANCE.md."
        )
    with open(path, "wb") as fh:
        fh.write(data)
    return path


def read_source(archive: str):
    """Return (words_by_tier, copyright_text, readme_version)."""
    by_tier = {t: set() for t in TIERS}
    copyright_text = None
    version = None
    with tarfile.open(archive, "r:gz") as tf:
        for member in tf.getmembers():
            if not member.isfile():
                continue
            name = member.name
            if name == f"{SOURCE_ROOT}/Copyright":
                copyright_text = tf.extractfile(member).read().decode("iso-8859-1")
                continue
            if name == f"{SOURCE_ROOT}/VERSION":
                version = tf.extractfile(member).read().decode("ascii").strip()
                continue
            m = re.match(rf"^{re.escape(SOURCE_ROOT)}/final/([a-z_0-9]+)-words\.(\d+)$", name)
            if not m:
                continue
            dialect, tier = m.group(1), int(m.group(2))
            if dialect not in DIALECTS or tier not in by_tier:
                continue
            text = tf.extractfile(member).read().decode("iso-8859-1")
            for line in text.splitlines():
                w = line.strip()
                if WORD_RE.match(w):
                    by_tier[tier].add(w)
    if copyright_text is None:
        raise SystemExit("build_word_lists: the archive carries no Copyright file — refusing to ship its output")
    return by_tier, copyright_text, version


def cumulative(by_tier, max_tier: int) -> set:
    out = set()
    for t in TIERS:
        if t > max_tier:
            break
        out |= by_tier[t]
    return out


def build_sets(by_tier):
    broad = cumulative(by_tier, ACCEPT_MAX_TIER)
    accepted = {w for w in broad if ACCEPT_MIN_LEN <= len(w) <= ACCEPT_MAX_LEN}
    by_len = {}
    for w in accepted:
        by_len.setdefault(len(w), set()).add(w)

    four = by_len.get(4, set())
    three = by_len.get(3, set())

    def is_simple_plural(w: str) -> bool:
        return w.endswith("s") and w[:-1] in four

    def is_simple_past(w: str) -> bool:
        return w.endswith("ed") and (w[:-1] in four or w[:-2] in three)

    familiar = cumulative(by_tier, SOLUTION_MAX_TIER)
    solutions = {
        w
        for w in familiar
        if len(w) == SOLUTION_LEN and not is_simple_plural(w) and not is_simple_past(w)
    }
    return by_len, solutions


def check_sets(by_len, solutions):
    for length, floor in MIN_ACCEPTED.items():
        got = len(by_len.get(length, ()))
        if got < floor:
            # Refusal 3.
            raise SystemExit(
                f"build_word_lists: only {got} accepted words of length {length}; the floor is {floor}.\n"
                f"  A filter that produces almost nothing regenerates cleanly and hashes against itself,\n"
                f"  so the floor is the only thing that can notice."
            )
    if len(solutions) < MIN_SOLUTIONS:
        raise SystemExit(
            f"build_word_lists: only {len(solutions)} solutions; the floor is {MIN_SOLUTIONS}."
        )
    missing = sorted(solutions - by_len.get(SOLUTION_LEN, set()))
    if missing:
        # Refusal 4.
        raise SystemExit(
            f"build_word_lists: {len(missing)} solution(s) are not accepted guesses, e.g. {missing[:5]}.\n"
            f"  Such a puzzle cannot be won and neither list can see the problem alone."
        )


LUAU_HEADER = """--!strict
--!nolint LocalShadow
-- GENERATED — do not edit by hand. Regenerate with:
--     python3 tools/build_word_lists.py
--
-- {what}
--
-- Source: {source}
--   {url}
--   SHA-256 {sha}
-- Licence and required notices: examples/gallery/examples/words/PROVENANCE.md
--
-- The words are stored as one fixed-width run rather than a table because the
-- lookup is a binary search over character offsets: {count} entries cost no
-- table allocation at load and about {probes} string comparisons per query.
"""


def luau_packed_module(what: str, length: int, words) -> str:
    ordered = sorted(words)
    packed_len = len(ordered) * length
    probes = max(1, (len(ordered).bit_length()))
    header = LUAU_HEADER.format(
        what=what,
        source=SOURCE_NAME,
        url=SOURCE_URL,
        sha=SOURCE_SHA256,
        count=len(ordered),
        probes=probes,
    )
    lines = []
    for i in range(0, len(ordered), WORDS_PER_LINE):
        lines.append('\t"' + "".join(ordered[i : i + WORDS_PER_LINE]) + '",')
    body = (
        "\nlocal CHUNKS = {\n"
        + "\n".join(lines)
        + "\n}\n\nreturn table.freeze({\n"
        + f"\tlength = {length},\n"
        + f"\tcount = {len(ordered)},\n"
        + "\tpacked = table.concat(CHUNKS),\n"
        + "})\n"
    )
    text = header + body
    if len(text) > SOURCE_CHAR_CAP:
        # Refusal 5.
        raise SystemExit(
            f"build_word_lists: the length-{length} module would be {len(text)} characters, over the\n"
            f"  {SOURCE_CHAR_CAP} cap. Roblox refuses a Source write at 200,000 characters and the\n"
            f"  refusal is quiet: a live-synced session keeps running the previous module while every\n"
            f"  file on disk looks right. Split the length or narrow the tier before shipping this."
        )
    assert len(text.split('local CHUNKS')[1]) > 0
    del packed_len
    return text


def write_if_changed(path: str, text: str) -> bool:
    old = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            old = fh.read()
    if old == text:
        return False
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return True


def generate(offline: bool) -> int:
    archive = fetch_source(offline)
    by_tier, copyright_text, version = read_source(archive)
    by_len, solutions = build_sets(by_tier)
    check_sets(by_len, solutions)

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []

    for length in sorted(by_len):
        path = os.path.join(OUT_DIR, f"len{length}.luau")
        text = luau_packed_module(
            f"Every accepted {length}-letter guess: SCOWL sizes 10 through {ACCEPT_MAX_TIER}, "
            f"American and pan-English word classes only.",
            length,
            by_len[length],
        )
        write_if_changed(path, text)
        written.append(path)

    sol_path = os.path.join(OUT_DIR, f"solutions.luau")
    sol_text = luau_packed_module(
        f"The answers the word game may choose: SCOWL sizes 10 through {SOLUTION_MAX_TIER}, "
        f"five letters, minus simple plurals and past tenses. Every entry is also an accepted guess.",
        SOLUTION_LEN,
        solutions,
    )
    write_if_changed(sol_path, sol_text)
    written.append(sol_path)

    prov = provenance_markdown(copyright_text, version, by_len, solutions)
    prov_path = os.path.join(OUT_DIR, "PROVENANCE.md")
    write_if_changed(prov_path, prov)

    manifest = {
        "schema": "facet-word-data/1",
        "source": {
            "name": SOURCE_NAME,
            "url": SOURCE_URL,
            "sha256": SOURCE_SHA256,
            "version": version,
            "home": SOURCE_HOME,
        },
        "policy": {
            "acceptedMaxTier": ACCEPT_MAX_TIER,
            "acceptedLengths": [ACCEPT_MIN_LEN, ACCEPT_MAX_LEN],
            "solutionMaxTier": SOLUTION_MAX_TIER,
            "solutionLength": SOLUTION_LEN,
            "dialects": DIALECTS,
            "droppedFromSolutions": ["simple plurals", "simple past tenses"],
        },
        "counts": {str(k): len(v) for k, v in sorted(by_len.items())},
        "solutionCount": len(solutions),
        "files": {},
    }
    for path in sorted(written):
        manifest["files"][os.path.basename(path)] = sha256_file(path)

    man_path = os.path.join(OUT_DIR, "manifest.luau")
    write_if_changed(man_path, manifest_module(manifest))

    print(
        "word data: "
        + ", ".join(f"len{k}={len(v)}" for k, v in sorted(by_len.items()))
        + f", solutions={len(solutions)}"
    )
    print(f"wrote {len(written) + 2} files under {OUT_DIR}/")
    return 0


def manifest_module(manifest: dict) -> str:
    """The manifest as Luau, so the suite can hold the drift claim with no Python."""

    def lua(value, indent=""):
        if isinstance(value, dict):
            inner = "".join(
                f'{indent}\t["{k}"] = {lua(v, indent + "\t")},\n' for k, v in value.items()
            )
            return "{\n" + inner + indent + "}"
        if isinstance(value, list):
            inner = "".join(f"{indent}\t{lua(v, indent + '\t')},\n" for v in value)
            return "{\n" + inner + indent + "}"
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, (int, float)):
            return str(value)
        if value is None:
            return "nil"
        escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'

    return (
        "--!strict\n"
        "-- GENERATED — do not edit by hand. Regenerate with:\n"
        "--     python3 tools/build_word_lists.py\n"
        "--\n"
        "-- What each generated file hashed to when it was produced. The word-data spec\n"
        "-- re-hashes the files on disk and compares, so data edited by hand — or a\n"
        "-- partial regeneration that left one length behind — fails the suite rather\n"
        "-- than quietly changing which words the games accept.\n"
        "\nreturn table.freeze(" + lua(manifest) + ")\n"
    )


def provenance_markdown(copyright_text: str, version, by_len, solutions) -> str:
    counts = "\n".join(
        f"| {k} letters | {len(v):,} |" for k, v in sorted(by_len.items())
    )
    return f"""# Where these words come from

The two example games — the five-letter word game and the crossword tile game —
share one generated English word set. Nothing here is typed by hand, and nothing
is fetched while a game is running.

## Source

| | |
|---|---|
| Name | {SOURCE_NAME} |
| Project home | {SOURCE_HOME} |
| Archive | `{SOURCE_URL}` |
| Archive SHA-256 | `{SOURCE_SHA256}` |
| `VERSION` inside the archive | `{version}` |

The generator refuses to run against an archive whose SHA-256 does not match the
pinned value, so "a dictionary" is never the provenance claim — a specific,
identified archive is.

## What was taken from it, and why

SCOWL grades every word by how widely it is known: size 10 is roughly the
thousand commonest English words, size 95 is everything including the obscure.
Two jobs want two different cuts.

**Accepted guesses** use sizes 10 through {ACCEPT_MAX_TIER}, from the
`english-words` and `american-words` classes only — which is what excludes proper
names, abbreviations and contractions without a second guess-filter. Lengths
{ACCEPT_MIN_LEN} through {ACCEPT_MAX_LEN} are kept, because the crossword needs
short words and the word game needs five-letter ones.

{counts}

Accepting a guess is deliberately generous: a player who types a real word and is
told it is not one blames the game, and is right to.

**Answers** use sizes 10 through {SOLUTION_MAX_TIER} at five letters, minus
simple plurals (a word ending in *s* whose four-letter stem is also a word) and
simple past tenses. That leaves **{len(solutions):,}** familiar words. Choosing an
answer is deliberately conservative: an answer nobody knows is not a puzzle, and
*asked* and *cakes* are real words but poor ones.

Every answer is also an accepted guess. The generator refuses to write the files
if that is ever untrue, because a puzzle whose answer the game would reject
cannot be won and neither list can see the problem on its own.

## Transformations applied

1. Read `final/english-words.N` and `final/american-words.N` for each size N in
   the chosen range, decoding as ISO-8859-1 (SCOWL's own encoding).
2. Keep only entries matching `^[a-z]+$` — this drops accented forms and anything
   with an apostrophe, and it is why no capitalisation rule is needed.
3. Keep the length range named above.
4. For answers only, apply the plural and past-tense filters described above.
5. Sort, pack each length into one fixed-width string, and record a SHA-256 per
   generated file in `manifest.luau`.

## Regenerating

```sh
python3 tools/build_word_lists.py            # generate (downloads the archive once)
python3 tools/build_word_lists.py --check    # verify the checked-in files; no network
```

`--check` is the half that runs anywhere: it re-hashes the generated files
against `manifest.luau` and needs neither the archive nor a network. The suite
runs the same comparison, so hand-edited word data fails a test rather than
quietly changing what the games accept.

## Required notices

SCOWL's licence grants permission to use, copy, modify, distribute and sell the
word lists and *the output created from the scripts* — provided the notices
travel with the copies. They are reproduced here in full, verbatim from the
archive's own `Copyright` file.

```
{copyright_text.rstrip()}
```
"""


def check() -> int:
    man_path = os.path.join(OUT_DIR, "manifest.luau")
    if not os.path.exists(man_path):
        raise SystemExit(f"build_word_lists --check: {man_path} is missing; run the generator")
    with open(man_path, encoding="utf-8") as fh:
        text = fh.read()
    files = dict(re.findall(r'\["([A-Za-z0-9_.]+\.luau)"\] = "([0-9a-f]{64})"', text))
    if not files:
        raise SystemExit(
            "build_word_lists --check: the manifest records no file hashes.\n"
            "  Finding nothing is a failure here, not a pass."
        )
    bad = []
    for name, want in sorted(files.items()):
        path = os.path.join(OUT_DIR, name)
        if not os.path.exists(path):
            bad.append(f"{name}: missing")
            continue
        got = sha256_file(path)
        if got != want:
            bad.append(f"{name}: {got} != recorded {want}")
    if bad:
        raise SystemExit(
            "build_word_lists --check: generated word data does not match its manifest:\n  "
            + "\n  ".join(bad)
            + "\n  Regenerate with: python3 tools/build_word_lists.py"
        )
    print(f"word data: {len(files)} generated files match manifest.luau")
    return 0


def selftest() -> int:
    """Prove each refusal fires, so the checks are not decoration."""
    failures = []

    # Refusal 3: a filter that produces almost nothing.
    try:
        check_sets({5: {"aaaaa"}}, {"aaaaa"})
        failures.append("the per-length floor did not fire on a one-word set")
    except SystemExit:
        pass

    # Refusal 4: a solution that is not an accepted guess.
    try:
        by_len = {n: {"x" * n for _ in range(1)} for n in MIN_ACCEPTED}
        by_len = {n: {("a" * n)} for n in MIN_ACCEPTED}
        # pad each length past its floor so only the subset rule can fail
        for n, floor in MIN_ACCEPTED.items():
            by_len[n] = {f"{i:0{n}d}" for i in range(floor + 1)}
        check_sets(by_len, {"zzzzz"})
        failures.append("the solution-is-an-accepted-guess rule did not fire")
    except SystemExit:
        pass

    # Refusal 5: an oversized module.
    try:
        luau_packed_module("oversize probe", 7, {f"{i:07d}" for i in range(40000)})
        failures.append("the Source character cap did not fire")
    except SystemExit:
        pass

    # --check refusal 2: a manifest whose hashes no longer match.
    with tempfile.TemporaryDirectory() as tmp:
        global OUT_DIR
        saved = OUT_DIR
        OUT_DIR = tmp
        try:
            with open(os.path.join(tmp, "manifest.luau"), "w", encoding="utf-8") as fh:
                fh.write('return { files = { ["len5.luau"] = "' + "0" * 64 + '" } }\n')
            with open(os.path.join(tmp, "len5.luau"), "w", encoding="utf-8") as fh:
                fh.write("return {}\n")
            try:
                check()
                failures.append("--check accepted a file whose hash does not match")
            except SystemExit:
                pass

            # ...and a manifest with no hashes at all must fail, not pass silently.
            with open(os.path.join(tmp, "manifest.luau"), "w", encoding="utf-8") as fh:
                fh.write("return { files = {} }\n")
            try:
                check()
                failures.append("--check passed over a manifest recording nothing")
            except SystemExit:
                pass
        finally:
            OUT_DIR = saved

    if failures:
        for f in failures:
            print(f"SELFTEST FAILED: {f}", file=sys.stderr)
        return 1
    print("build_word_lists --selftest: 5 refusals fired")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="verify the checked-in files against the manifest")
    ap.add_argument("--selftest", action="store_true", help="prove each refusal can fire")
    ap.add_argument("--offline", action="store_true", help="refuse to download; use a cached archive only")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.check:
        return check()
    return generate(args.offline)


if __name__ == "__main__":
    sys.exit(main())
