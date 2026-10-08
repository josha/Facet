#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

from strip_comments import LONG_OPEN, LuauScanner


ROOT = Path(__file__).resolve().parents[1]
BUDGET = ROOT / "tools/typecheck/any_budget.json"
DIRECTORIES = ("src", "examples", "tools", "tests", "bench")


class TypeScanner(LuauScanner):
    def __init__(self, source):
        super().__init__(source)
        self.uses = []

    def code(self, index=0, interpolation=False):
        depth = 0
        while index < len(self.source):
            char = self.source[index]
            if self.source.startswith("--", index):
                opened = LONG_OPEN.match(self.source, index + 2)
                end = self.long(opened) if opened else self.source.find("\n", index)
                index = len(self.source) if end < 0 else end
            elif char in "\"'":
                index = self.quoted(index)
            elif char == "`":
                index = self.interpolated(index)
            elif char == "[" and (opened := LONG_OPEN.match(self.source, index)):
                index = self.long(opened)
            elif interpolation and char == "}" and depth == 0:
                return index + 1
            elif char.isalpha() or char == "_":
                word = re.match(r"[A-Za-z_][A-Za-z_0-9]*", self.source[index:])
                if word is None:
                    index += 1
                    continue
                if word.group() == "any":
                    self.uses.append(index)
                index += len(word.group())
            else:
                if char == "{":
                    depth += 1
                elif char == "}":
                    depth -= 1
                index += 1
        if interpolation:
            raise ValueError("unterminated Luau interpolation expression")
        return index


def uses(source):
    scanner = TypeScanner(source)
    scanner.code()
    return [source.count("\n", 0, position) + 1 for position in scanner.uses]


def inventory(root, directories=DIRECTORIES):
    counts = {}
    source_uses = []
    for directory in directories:
        count = 0
        for path in sorted((root / directory).rglob("*")):
            if not path.is_file() or path.suffix not in {".lua", ".luau"} or "vendor" in path.relative_to(root).parts:
                continue
            try:
                lines = uses(path.read_text())
            except ValueError as error:
                raise ValueError(f"{path.relative_to(root)}: {error}") from error
            count += len(lines)
            if directory == "src":
                source_uses.extend(f"{path.relative_to(root)}:{line}" for line in lines)
        counts[directory] = count
    return counts, source_uses


def violations(counts, budget):
    errors = []
    if counts["src"]:
        errors.append(f"src contains {counts['src']} forbidden any types")
    for directory in DIRECTORIES[1:]:
        limit = budget[directory]
        if limit is not None and counts[directory] > limit:
            errors.append(f"{directory}: {counts[directory]} any types exceeds budget {limit}")
    return errors


def lower_budget(counts, budget):
    for directory in DIRECTORIES[1:]:
        old = budget[directory]
        if old is not None and counts[directory] > old:
            raise ValueError(f"cannot raise {directory} budget from {old} to {counts[directory]}")
    return {directory: counts[directory] for directory in DIRECTORIES[1:]}


class PolicyTests(unittest.TestCase):
    def test_annotations_casts_and_nested_types(self):
        self.assertEqual(len(uses("local x: any = y :: any; type T = (any) -> {any}")), 4)

    def test_strings_comments_and_identifiers(self):
        self.assertEqual(uses('local many = "any"; local s = [=[any]=] -- any\n--[==[any]==]'), [])
        self.assertEqual(uses("local s = 'escaped \\' any'"), [])

    def test_interpolation_expressions(self):
        self.assertEqual(len(uses('local s = `any {x :: any} {`any {y :: any}`}`')), 2)
        self.assertEqual(uses('local s = `any \\{any\\}`'), [])

    def test_budget(self):
        counts = dict.fromkeys(DIRECTORIES, 0)
        budget = dict.fromkeys(DIRECTORIES[1:], 0)
        self.assertEqual(violations(counts, budget), [])
        counts["examples"] = 1
        self.assertEqual(len(violations(counts, budget)), 1)
        counts["src"] = 1
        self.assertEqual(len(violations(counts, budget)), 2)

    def test_budget_can_only_decrease_and_pending_tests_can_be_set(self):
        counts = dict.fromkeys(DIRECTORIES, 2)
        budget = dict.fromkeys(DIRECTORIES[1:], 3)
        budget["tests"] = None
        self.assertEqual(lower_budget(counts, budget)["tests"], 2)
        counts["tools"] = 4
        with self.assertRaises(ValueError):
            lower_budget(counts, budget)

    def test_invalid_source_fails(self):
        with self.assertRaises(ValueError):
            uses("local value: any = 'unfinished")

    def test_inventory_excludes_vendor_and_counts_each_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for directory in DIRECTORIES:
                target = root / directory
                target.mkdir()
                (target / "main.luau").write_text("local value: any = 'any'")
                vendor = target / "vendor"
                vendor.mkdir()
                (vendor / "dependency.luau").write_text("type Value = any | any")
            counts, locations = inventory(root)
            self.assertEqual(counts, dict.fromkeys(DIRECTORIES, 1))
            self.assertEqual(locations, ["src/main.luau:1"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--counts", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--lower-budgets", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(PolicyTests)).wasSuccessful() else 1
    if args.counts:
        counts, _ = inventory(ROOT)
        print(json.dumps(counts, indent=2))
        return 0
    budget = json.loads(BUDGET.read_text())
    directories = DIRECTORIES if args.lower_budgets or budget["tests"] is not None else tuple(
        directory for directory in DIRECTORIES if directory != "tests"
    )
    counts, locations = inventory(ROOT, directories)
    if args.lower_budgets:
        BUDGET.write_text(json.dumps(lower_budget(counts, budget), indent=2) + "\n")
        budget = json.loads(BUDGET.read_text())
    errors = violations(counts, budget)
    print(json.dumps(counts, sort_keys=True))
    if budget["tests"] is None:
        print("tests budget pending: lead must run --lower-budgets after the test edits")
    for message in errors + locations:
        print(message, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as error:
        print(f"type policy: FAIL; {error}", file=sys.stderr)
        raise SystemExit(1)
