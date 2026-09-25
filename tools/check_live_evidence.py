#!/usr/bin/env python3
import argparse
import copy
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARITY = os.path.join("tools", "lune", "parity_blockers.json")
COVERAGE_GLOB = os.path.join("tools", "lune", "coverage_*.json")
GAP_CLOSURE = os.path.join("artifacts", "compose-simplification", "gap-closure-live.json")
CAPTURE_DIRS = (
    os.path.join("artifacts", "performance-stress-places", "studio"),
    os.path.join("artifacts", "cross-platform-proof", "device"),
)
PARITY_SCHEMA = "facet-product-parity-blockers/1"
GAP_SCHEMA = "facet-gap-closure-live/1"
DEVICE_CLASSES = ("phone", "tablet", "console", "desktop", "gamepad")
PHYSICAL_HOST = re.compile(r"\bphysical (" + "|".join(DEVICE_CLASSES) + r")\b", re.IGNORECASE)
PHYSICAL_WORD = re.compile(r"\bphysical\b", re.IGNORECASE)
NEGATION = re.compile(r"\b(not|no|never|pending|only|without|cannot)\b", re.IGNORECASE)
STUDIO_HOST = re.compile(r"\broblox studio\b", re.IGNORECASE)
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ITEM_ID = re.compile(r"^[A-Z]+\d+$")
COMMIT_REF = re.compile(r"^([0-9a-f]{7,40}) (\S.*)$")
ARTIFACT_PATH = re.compile(r"artifacts/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]+")
CALL = re.compile(r"(?<![\w.:])(?:[A-Za-z_]\w*\.)?(describe|it)\s*\(")
ITEM_FIELDS = {
    "id": str,
    "sourceReference": str,
    "requiredEvidence": str,
    "cases": list,
    "remaining": list,
    "resolution": str,
}
EVIDENCE_META = ("date", "host", "hosts", "headless")


def git(*args):
    return subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True)


class Git:
    def __init__(self):
        self.cache = {}

    def commit(self, sha):
        if sha not in self.cache:
            exists = git("cat-file", "-e", f"{sha}^{{commit}}").returncode == 0
            info = None
            if exists:
                shown = git("show", "-s", "--format=%cs%x00%s", sha).stdout.strip().split("\x00", 1)
                ancestor = git("merge-base", "--is-ancestor", sha, "HEAD").returncode == 0
                info = {"date": shown[0], "subject": shown[1] if len(shown) > 1 else "", "ancestor": ancestor}
            self.cache[sha] = info
        return self.cache[sha]

    def tracked(self, path):
        key = ("tracked", path)
        if key not in self.cache:
            self.cache[key] = git("ls-files", "--error-unmatch", "--", path).returncode == 0
        return self.cache[key]


def lua_string(text, index):
    quote = text[index]
    out = []
    index += 1
    while index < len(text) and text[index] != quote:
        if text[index] == "\\" and index + 1 < len(text):
            escaped = text[index + 1]
            out.append({"n": "\n", "t": "\t"}.get(escaped, escaped))
            index += 2
            continue
        out.append(text[index])
        index += 1
    return "".join(out), index + 1


def template_string(text, index):
    parts = []
    literal = []
    index += 1
    while index < len(text) and text[index] != "`":
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            literal.append(text[index + 1])
            index += 2
            continue
        if char == "{":
            parts.append(("lit", "".join(literal)))
            literal = []
            depth = 1
            index += 1
            while index < len(text) and depth:
                depth += {"{": 1, "}": -1}.get(text[index], 0)
                index += 1
            parts.append(("any", None))
            continue
        literal.append(char)
        index += 1
    parts.append(("lit", "".join(literal)))
    return parts, index + 1


def expression(text, index):
    depth = 0
    while index < len(text):
        char = text[index]
        if char in "\"'":
            _, index = lua_string(text, index)
            continue
        if char in "([{":
            depth += 1
        elif char in ")]}":
            if depth == 0:
                return index
            depth -= 1
        elif depth == 0 and (char == "," or text.startswith("..", index)):
            return index
        index += 1
    return index


def call_name(text, index):
    parts = []
    while True:
        while index < len(text) and text[index] in " \t\r\n":
            index += 1
        if index >= len(text):
            return None
        char = text[index]
        if char in "\"'":
            value, index = lua_string(text, index)
            parts.append(("lit", value))
        elif char == "`":
            pieces, index = template_string(text, index)
            parts.extend(pieces)
        else:
            end = expression(text, index)
            if end == index:
                return None
            parts.append(("any", None))
            index = end
        while index < len(text) and text[index] in " \t\r\n":
            index += 1
        if text.startswith("..", index):
            index += 2
            continue
        break
    if all(kind == "lit" for kind, _ in parts):
        return "".join(value for _, value in parts)
    return re.compile("^" + "".join(re.escape(value) if kind == "lit" else ".+" for kind, value in parts) + "$")


def spec_cases(path):
    text = open(path, encoding="utf-8").read()
    stack = []
    cases = []
    for match in CALL.finditer(text):
        line_start = text.rfind("\n", 0, match.start()) + 1
        indent = len(text[line_start : match.start()].expandtabs(4)) - len(text[line_start : match.start()].expandtabs(4).lstrip())
        name = call_name(text, match.end())
        if name is None:
            continue
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if match.group(1) == "describe":
            stack.append((indent, name))
        elif stack and isinstance(stack[-1][1], str):
            cases.append((stack[-1][1], name))
    return cases


class Registry:
    def __init__(self, tests_root):
        self.specs = {}
        for path in sorted(glob.glob(os.path.join(tests_root, "**", "*.luau"), recursive=True)):
            relative = os.path.relpath(path, tests_root).replace(os.sep, "/")
            if relative.startswith("lib/"):
                continue
            if relative.endswith(".spec.luau"):
                name = relative[: -len(".spec.luau")]
            elif relative.endswith("_spec.luau"):
                name = relative[: -len(".luau")]
            else:
                continue
            self.specs[name] = spec_cases(path)

    def count(self):
        return sum(len(cases) for cases in self.specs.values())

    def check(self, case_id):
        parts = case_id.split("::")
        if len(parts) != 3 or not all(part.strip() for part in parts):
            return "case-format", f"'{case_id}' is not spec::describe::it"
        spec, describe, name = parts
        if spec not in self.specs:
            return "unknown-case", f"'{case_id}' names spec '{spec}', which has no tests/{spec}.spec.luau"
        for suite, case in self.specs[spec]:
            if suite != describe:
                continue
            if case == name if isinstance(case, str) else case.match(name):
                return None
        return "unknown-case", f"'{case_id}' is not a registered describe/it in tests/{spec}.spec.luau"


class Checker:
    def __init__(self, root, registry, git_state, today):
        self.root = root
        self.registry = registry
        self.git = git_state
        self.today = today
        self.findings = []
        self.reports = []
        self.cited = set()
        self.stats = {"items": 0, "cases": 0, "resolvedRisks": 0, "liveEvidence": 0, "artifacts": 0}

    def fail(self, rule, where, message):
        self.findings.append(f"[{rule}] {where}: {message}")

    def load(self, relative):
        path = os.path.join(self.root, relative)
        try:
            with open(path, encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, ValueError) as error:
            self.fail("schema", relative, f"cannot read JSON: {error}")
            return None

    def text(self, where, value, field, required=True):
        if value is None and not required:
            return False
        if not isinstance(value, str) or not value.strip():
            self.fail("schema", where, f"'{field}' must be a non-empty string")
            return False
        return True

    def case(self, where, case_id):
        self.stats["cases"] += 1
        if not isinstance(case_id, str):
            self.fail("schema", where, f"case {case_id!r} is not a string")
            return
        problem = self.registry.check(case_id)
        if problem:
            self.fail(problem[0], where, problem[1])

    def artifacts(self, where, value):
        if isinstance(value, dict):
            for child in value.values():
                self.artifacts(where, child)
        elif isinstance(value, list):
            for child in value:
                self.artifacts(where, child)
        elif isinstance(value, str):
            for path in ARTIFACT_PATH.findall(value):
                self.stats["artifacts"] += 1
                if (where, path) in self.cited:
                    continue
                self.cited.add((where, path))
                if not os.path.isfile(os.path.join(REPO, path)):
                    self.fail("artifact", where, f"cites {path}, which does not exist")
                elif not self.git.tracked(path):
                    self.fail("artifact", where, f"cites {path}, which is not tracked by git and would not survive a clone")

    def commit(self, where, sha, subject=None):
        info = self.git.commit(sha)
        if info is None:
            self.fail("commit", where, f"{sha} is not a commit in this repository")
            return None
        if not info["ancestor"]:
            self.fail("commit", where, f"{sha} is not in the history of HEAD")
        if subject is not None and subject != info["subject"]:
            self.fail("commit", where, f"{sha} is recorded as '{subject}' but its subject is '{info['subject']}'")
        return info

    def date(self, where, value, floor=None):
        if not isinstance(value, str) or not ISO_DATE.match(value):
            self.fail("date", where, f"date {value!r} is not an ISO YYYY-MM-DD date")
            return
        try:
            parsed = datetime.date.fromisoformat(value)
        except ValueError:
            self.fail("date", where, f"date {value!r} is not a calendar date")
            return
        if parsed > self.today:
            self.fail("date", where, f"date {value} is in the future")
        if floor is not None and value < floor:
            self.fail("date", where, f"evidence dated {value} predates the resolving commit dated {floor}")

    def host_class(self, where, host):
        studio = bool(STUDIO_HOST.search(host))
        physical = PHYSICAL_HOST.search(host)
        if studio and physical:
            self.fail("host", where, f"host '{host}' names both Roblox Studio and a physical device; record one host per class")
            return None
        if studio:
            return ("studio", None)
        if physical:
            return ("physical", physical.group(1).lower())
        if PHYSICAL_WORD.search(host):
            self.fail("host", where, f"host '{host}' claims a physical device without stating its class ({', '.join(DEVICE_CLASSES)})")
        else:
            self.fail("host", where, f"host '{host}' names neither Roblox Studio nor a physical device with its class")
        return None

    def studio_claims(self, where, value):
        if isinstance(value, dict):
            for child in value.values():
                self.studio_claims(where, child)
        elif isinstance(value, list):
            for child in value:
                self.studio_claims(where, child)
        elif isinstance(value, str) and PHYSICAL_HOST.search(value) and not NEGATION.search(value):
            self.fail("evidence-class", where, f"Studio-hosted evidence claims a physical-device result: '{value[:120]}'")

    def live_entry(self, where, entry):
        self.stats["liveEvidence"] += 1
        if not isinstance(entry, dict):
            self.fail("schema", where, "a liveEvidence entry must be an object")
            return
        self.text(where, entry.get("artifact"), "artifact")
        self.text(where, entry.get("stamp"), "stamp")
        self.text(where, entry.get("observed"), "observed")
        if "date" in entry:
            self.date(where, entry["date"])
        if "host" in entry and self.text(where, entry["host"], "host"):
            self.host_class(where, entry["host"])

    def parity(self):
        data = self.load(PARITY)
        if not isinstance(data, dict):
            return
        if data.get("schema") != PARITY_SCHEMA:
            self.fail("schema", PARITY, f"schema must be '{PARITY_SCHEMA}', found {data.get('schema')!r}")
        if self.text(PARITY, data.get("baselineCommit"), "baselineCommit"):
            self.commit(f"{PARITY} baselineCommit", data["baselineCommit"])
        self.text(PARITY, data.get("note"), "note")
        self.text(PARITY, data.get("audit"), "audit")
        self.artifacts(PARITY, data)
        for field in ("items", "pendingLiveRisks", "resolvedLiveRisks"):
            if not isinstance(data.get(field), list):
                self.fail("schema", PARITY, f"'{field}' must be a list")
                data[field] = []
        seen = set()
        for index, item in enumerate(data["items"]):
            self.item(index, item, seen)
        pending = set()
        for index, risk in enumerate(data["pendingLiveRisks"]):
            where = f"{PARITY} pendingLiveRisks[{index}]"
            if self.text(where, risk, "risk"):
                if risk in pending:
                    self.fail("duplicate-risk", where, f"'{risk}' is listed twice")
                pending.add(risk)
                self.reports.append(f"pending live risk: {risk}")
        resolved = set()
        for index, record in enumerate(data["resolvedLiveRisks"]):
            self.resolved(index, record, pending, resolved)

    def item(self, index, item, seen):
        self.stats["items"] += 1
        where = f"{PARITY} items[{index}]"
        if not isinstance(item, dict):
            self.fail("schema", where, "an item must be an object")
            return
        if isinstance(item.get("id"), str):
            where = f"{PARITY} {item['id']}"
        for field, kind in ITEM_FIELDS.items():
            value = item.get(field)
            if value is None:
                self.fail("schema", where, f"missing '{field}'")
            elif not isinstance(value, kind):
                self.fail("schema", where, f"'{field}' must be a {kind.__name__}")
            elif kind is str and not value.strip():
                self.fail("schema", where, f"'{field}' is empty")
        unknown = set(item) - set(ITEM_FIELDS) - {"liveEvidence"}
        if unknown:
            self.fail("schema", where, f"unknown fields {sorted(unknown)}")
        ident = item.get("id")
        if isinstance(ident, str):
            if not ITEM_ID.match(ident):
                self.fail("schema", where, f"id '{ident}' does not match {ITEM_ID.pattern}")
            if ident in seen:
                self.fail("duplicate-id", where, f"id '{ident}' is used by more than one item")
            seen.add(ident)
        cases = item.get("cases") if isinstance(item.get("cases"), list) else []
        if len(cases) != len({case for case in cases if isinstance(case, str)}):
            self.fail("schema", where, "cases repeat or contain non-strings")
        for case in cases:
            self.case(where, case)
        remaining = item.get("remaining") if isinstance(item.get("remaining"), list) else None
        if remaining is not None:
            for gap in remaining:
                self.text(where, gap, "remaining[]")
        live = item.get("liveEvidence")
        if live is not None:
            if not isinstance(live, list) or not live:
                self.fail("schema", where, "'liveEvidence' must be a non-empty list when present")
                live = []
            for position, entry in enumerate(live):
                self.live_entry(f"{where} liveEvidence[{position}]", entry)
        if remaining == []:
            if not cases and not live:
                self.fail("resolved-without-evidence", where, "resolved (empty remaining) but cites neither cases nor liveEvidence")
        elif remaining:
            self.reports.append(f"open parity item {ident}: {'; '.join(str(gap) for gap in remaining)}")

    def resolved(self, index, record, pending, resolved):
        self.stats["resolvedRisks"] += 1
        where = f"{PARITY} resolvedLiveRisks[{index}]"
        if not isinstance(record, dict):
            self.fail("schema", where, "a resolved risk must be an object")
            return
        risk = record.get("risk")
        if self.text(where, risk, "risk"):
            where = f"{PARITY} resolved '{risk[:48]}'"
            if risk in resolved:
                self.fail("duplicate-risk", where, "resolved twice")
            if risk in pending:
                self.fail("duplicate-risk", where, "listed as both pending and resolved")
            resolved.add(risk)
        refs = record.get("resolvedBy")
        refs = [refs] if isinstance(refs, str) else refs
        floor = None
        if refs is None:
            refs = []
        elif not isinstance(refs, list) or not refs:
            self.fail("schema", where, "'resolvedBy' must be a commit reference or a non-empty list of them")
            refs = []
        for ref in refs:
            parsed = COMMIT_REF.match(ref) if isinstance(ref, str) else None
            if not parsed:
                self.fail("commit", where, f"resolvedBy {ref!r} is not '<sha> <subject>'")
                continue
            info = self.commit(where, parsed.group(1), parsed.group(2))
            if info and (floor is None or info["date"] > floor):
                floor = info["date"]
        evidence = record.get("evidence")
        if not isinstance(evidence, dict):
            self.fail("schema", where, "'evidence' must be an object")
            return
        self.date(where, evidence.get("date"), floor)
        hosts = evidence.get("hosts") if "hosts" in evidence else [evidence.get("host")]
        if "host" in evidence and "hosts" in evidence:
            self.fail("schema", where, "record either 'host' or 'hosts', not both")
        if not isinstance(hosts, list) or not hosts:
            self.fail("schema", where, "'hosts' must be a non-empty list")
            hosts = []
        classes = []
        for host in hosts:
            if self.text(where, host, "host"):
                found = self.host_class(where, host)
                if found:
                    classes.append(found)
        headless = evidence.get("headless")
        if not isinstance(headless, list) or not headless:
            self.fail("schema", where, "'headless' must list the headless cases that pin the fix")
        else:
            for case in headless:
                self.case(where, case)
        observations = [key for key, value in evidence.items() if key not in EVIDENCE_META and isinstance(value, str) and value.strip()]
        if not observations:
            self.fail("schema", where, "evidence records no observation (steps, before/after or named checks)")
        if ("before" in evidence) != ("after" in evidence):
            self.fail("before-after", where, "a before observation needs its after, and an after needs its before")
        if isinstance(risk, str) and PHYSICAL_WORD.search(risk):
            required = {name for name in DEVICE_CLASSES if re.search(rf"\b{name}s?\b", risk, re.IGNORECASE)}
            covered = {device for kind, device in classes if kind == "physical"}
            if any(kind != "physical" for kind, _ in classes) or not classes:
                self.fail("evidence-class", where, "a physical-device risk cannot be resolved by Studio or emulator evidence")
            missing = required - covered
            if missing:
                self.fail("evidence-class", where, f"no physical host covers {sorted(missing)}")
        if classes and all(kind == "studio" for kind, _ in classes):
            self.studio_claims(where, {key: value for key, value in evidence.items() if key not in ("host", "hosts")})

    def coverage(self):
        for path in sorted(glob.glob(os.path.join(self.root, COVERAGE_GLOB))):
            relative = os.path.relpath(path, self.root)
            data = self.load(relative)
            if data is None:
                continue
            self.artifacts(relative, data)
            self.walk_coverage(relative, data, relative)

    def walk_coverage(self, relative, value, where):
        if isinstance(value, dict):
            for key, child in value.items():
                label = f"{where}/{key}"
                if key == "liveEvidence":
                    if not isinstance(child, list) or not child:
                        self.fail("schema", label, "'liveEvidence' must be a non-empty list")
                        continue
                    for position, entry in enumerate(child):
                        self.live_entry(f"{label}[{position}]", entry)
                elif key == "pendingLiveRisks" and isinstance(child, list):
                    for risk in child:
                        self.reports.append(f"pending live risk ({relative}): {risk}")
                else:
                    self.walk_coverage(relative, child, label)
        elif isinstance(value, list):
            for child in value:
                self.walk_coverage(relative, child, where)

    def gap_closure(self):
        if not os.path.isfile(os.path.join(self.root, GAP_CLOSURE)):
            self.reports.append(f"{GAP_CLOSURE} absent; skipped")
            return
        data = self.load(GAP_CLOSURE)
        if not isinstance(data, dict):
            return
        if data.get("schema") != GAP_SCHEMA:
            self.fail("schema", GAP_CLOSURE, f"schema must be '{GAP_SCHEMA}'")
        self.text(GAP_CLOSURE, data.get("studio"), "studio")
        self.text(GAP_CLOSURE, data.get("device"), "device")
        stamp = data.get("candidateStamp")
        if not isinstance(stamp, str) or not re.match(r"^[0-9a-f]{6,64}$", stamp):
            self.fail("schema", GAP_CLOSURE, "'candidateStamp' must be a hex build stamp")
        if not isinstance(data.get("evidence"), dict) or not data["evidence"]:
            self.fail("schema", GAP_CLOSURE, "'evidence' must be a non-empty object")
        self.studio_claims(GAP_CLOSURE, data.get("evidence"))
        self.artifacts(GAP_CLOSURE, data)

    def captures(self):
        for relative in CAPTURE_DIRS:
            if os.path.isdir(os.path.join(self.root, relative)):
                self.reports.append(f"{relative} present; its rows are validated by tools/check_perf_captures.py")
            else:
                self.reports.append(f"{relative} absent; no capture rows to validate")

    def run(self):
        self.parity()
        self.coverage()
        self.gap_closure()
        self.captures()
        return self


def check(root=REPO, registry=None, git_state=None, today=None):
    return Checker(
        root,
        registry or Registry(os.path.join(REPO, "tests")),
        git_state or Git(),
        today or datetime.date.today(),
    ).run()


def plant_tree(mutate):
    work = tempfile.mkdtemp(prefix="facet-live-evidence-")
    for relative in [PARITY, GAP_CLOSURE] + [os.path.relpath(path, REPO) for path in glob.glob(os.path.join(REPO, COVERAGE_GLOB))]:
        source = os.path.join(REPO, relative)
        if os.path.isfile(source):
            os.makedirs(os.path.dirname(os.path.join(work, relative)), exist_ok=True)
            shutil.copy2(source, os.path.join(work, relative))
    path = os.path.join(work, PARITY)
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    gap_path = os.path.join(work, GAP_CLOSURE)
    gap = None
    if os.path.isfile(gap_path):
        with open(gap_path, encoding="utf-8") as handle:
            gap = json.load(handle)
    mutate(data, gap)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    if gap is not None:
        with open(gap_path, "w", encoding="utf-8") as handle:
            json.dump(gap, handle)
    return work


def first_resolved(data):
    return data["resolvedLiveRisks"][0]


def haptic_to_studio(data, _gap):
    risk = next((risk for risk in data["pendingLiveRisks"] if "physical" in risk), None)
    if risk is None:
        risk = "Haptic motor output on a physical gamepad (planted by the selftest)"
    else:
        data["pendingLiveRisks"].remove(risk)
    record = copy.deepcopy(first_resolved(data))
    record["risk"] = risk
    data["resolvedLiveRisks"].append(record)


def haptic_to_phone_only(data, _gap):
    risk = next((risk for risk in data["pendingLiveRisks"] if "physical" in risk), None)
    if risk is None:
        risk = "Haptic motor output on a physical gamepad (planted by the selftest)"
    else:
        data["pendingLiveRisks"].remove(risk)
    record = copy.deepcopy(first_resolved(data))
    record["risk"] = risk
    record["evidence"]["host"] = "Physical phone device: Pixel 8, Roblox app"
    data["resolvedLiveRisks"].append(record)


def set_evidence(field, value):
    def mutate(data, _gap):
        first_resolved(data)["evidence"][field] = value

    return mutate


def drop_evidence(field):
    def mutate(data, _gap):
        first_resolved(data)["evidence"].pop(field, None)

    return mutate


def set_item(field, value):
    def mutate(data, _gap):
        data["items"][0][field] = value

    return mutate


def drop_item(field):
    def mutate(data, _gap):
        data["items"][0].pop(field, None)

    return mutate


def duplicate_item(data, _gap):
    data["items"].append(copy.deepcopy(data["items"][0]))


def unresolved_bare(data, _gap):
    data["items"][0]["cases"] = []
    data["items"][0].pop("liveEvidence", None)


def resolved_by(value):
    def mutate(data, _gap):
        first_resolved(data)["resolvedBy"] = value

    return mutate


def pending_and_resolved(data, _gap):
    data["pendingLiveRisks"].append(first_resolved(data)["risk"])


def live_entry(entry):
    def mutate(data, _gap):
        data["items"][0]["liveEvidence"] = [entry]

    return mutate


def gap_physical(_data, gap):
    gap["evidence"]["phoneTouch"]["device"] = "physical phone Pixel 8"


def studio_physical_claim(data, _gap):
    first_resolved(data)["evidence"]["steps"] = "Confirmed on a physical phone in the Roblox app."


def selftest():
    registry = Registry(os.path.join(REPO, "tests"))
    git_state = Git()
    today = datetime.date.today()
    head_sha = git("rev-parse", "HEAD").stdout.strip()
    head_subject = git("log", "-1", "--format=%s", "HEAD").stdout.strip()

    def early_fix(data, gap):
        resolved_by(f"{head_sha[:8]} {head_subject}")(data, gap)
        set_evidence("date", "2000-01-01")(data, gap)
    tomorrow = (today + datetime.timedelta(days=1)).isoformat()
    good_entry = {"artifact": GAP_CLOSURE, "stamp": "abc123", "observed": "Selection moved into the shown panel."}
    plants = [
        ("an item id used twice", duplicate_item, "duplicate-id"),
        ("an item without requiredEvidence", drop_item("requiredEvidence"), "schema"),
        ("an item whose cases is a string", set_item("cases", "native_navigation::x::y"), "schema"),
        ("a resolved item with neither cases nor liveEvidence", unresolved_bare, "resolved-without-evidence"),
        ("a case id that no spec registers", set_item("cases", ["native_navigation::native navigation controls::does a thing nobody wrote"]), "unknown-case"),
        ("a case id without its describe", set_item("cases", ["native_navigation::hands selection to the shown tab panel and restores it on return"]), "case-format"),
        ("a case in a spec that does not exist", set_item("cases", ["native_nowhere::suite::case"]), "unknown-case"),
        ("liveEvidence citing an artifact that was never recorded", live_entry(dict(good_entry, artifact="artifacts/compose-simplification/never-recorded.json")), "artifact"),
        ("liveEvidence without its observation", live_entry({"artifact": GAP_CLOSURE, "stamp": "abc123"}), "schema"),
        ("a baselineCommit that is not a commit", lambda data, _gap: data.update(baselineCommit="0" * 40), "commit"),
        ("resolved evidence dated tomorrow", set_evidence("date", tomorrow), "date"),
        ("resolved evidence with a non-ISO date", set_evidence("date", "23 September 2026"), "date"),
        ("resolved evidence dated before its fix landed", early_fix, "date"),
        ("a host that is neither Studio nor a device", set_evidence("host", "my laptop, 1280x720"), "host"),
        ("a physical host with no device class", set_evidence("host", "a physical device in the lab"), "host"),
        ("resolvedBy naming a commit that does not exist", resolved_by("deadbeef1 Fix something"), "commit"),
        ("resolvedBy whose subject disagrees with git", resolved_by(f"{head_sha[:8]} A subject this commit does not have"), "commit"),
        ("resolvedBy without a subject", resolved_by(head_sha[:8]), "commit"),
        ("a headless case that is not registered", set_evidence("headless", ["native_navigation::native navigation controls::imaginary"]), "unknown-case"),
        ("resolved evidence without headless cases", drop_evidence("headless"), "schema"),
        ("a before observation with no after", drop_evidence("after"), "before-after"),
        ("a risk listed as both pending and resolved", pending_and_resolved, "duplicate-risk"),
        ("the haptic motor risk resolved by a Studio host", haptic_to_studio, "evidence-class"),
        ("the haptic motor risk resolved on a phone but not a gamepad", haptic_to_phone_only, "evidence-class"),
        ("Studio evidence that claims a physical-phone result", studio_physical_claim, "evidence-class"),
        ("a Studio gap-closure record that claims a physical phone", gap_physical, "evidence-class"),
    ]
    control = check(registry=registry, git_state=git_state, today=today)
    baseline = set(control.findings)
    print(f"  control: {len(baseline)} finding(s) on the unplanted tree, {control.stats['cases']} cited cases resolved against {registry.count()} registered cases")
    ok = True
    for label, mutate, rule in plants:
        work = plant_tree(mutate)
        try:
            result = check(root=work, registry=registry, git_state=git_state, today=today)
        finally:
            shutil.rmtree(work, ignore_errors=True)
        fresh = [finding for finding in result.findings if finding not in baseline]
        bitten = [finding for finding in fresh if finding.startswith(f"[{rule}]")]
        print(f"  [{'BITES' if bitten else 'MISSED'}] {label}")
        for finding in (bitten or fresh)[:1]:
            print(f"      -> {finding}")
        if not bitten:
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(description="Validate recorded Studio and device live evidence.")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        print("check_live_evidence --selftest")
        passed = selftest()
        print("check_live_evidence --selftest: " + ("every rule bites" if passed else "a rule did not bite"))
        raise SystemExit(0 if passed else 1)
    result = check()
    for line in result.reports:
        print(f"  note: {line}")
    stats = result.stats
    summary = (
        f"{stats['items']} parity items, {stats['resolvedRisks']} resolved live risks, "
        f"{stats['liveEvidence']} liveEvidence entries, {stats['cases']} cited cases, {stats['artifacts']} artifact citations"
    )
    if result.findings:
        print(f"check_live_evidence: {len(result.findings)} finding(s) across {summary}")
        for finding in result.findings:
            print(f"  - {finding}")
        if all(finding.startswith("[artifact]") for finding in result.findings):
            print("check_live_evidence: FAIL_ENVIRONMENT - the records are well formed, but cited evidence is not in this checkout")
            raise SystemExit(2)
        raise SystemExit(1)
    print(f"check_live_evidence: ok ({summary})")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
