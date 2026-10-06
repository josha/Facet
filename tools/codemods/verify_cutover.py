import argparse
import collections
import json
from pathlib import Path
import re
import subprocess

from tree_sitter import Language, Parser
import tree_sitter_luau

PARSER = Parser(Language(tree_sitter_luau.language()))
MATCHERS = {"toBe", "toEqual", "toBeTruthy", "toBeFalsy", "toBeNil", "toBeCloseTo", "toBeGreaterThan", "toBeGreaterThanOrEqual", "toBeLessThan", "toBeLessThanOrEqual", "toThrow"}


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def arguments(node):
    return [child for child in node.children[1].named_children if child.type != "comment"]


def literal(node):
    value = node.text.decode()
    if node.type != "string" or value.startswith("`"):
        return None
    return json.loads(value) if value.startswith('"') else value[1:-1]


def transform(source, spec):
    source = source.replace('local testkit = require("./lib/testkit")', 'local t = require("./lib/testkit")').replace("testkit.describe, testkit.it, testkit.expect", "t.describe, t.it, t.expect")
    aliased = "local describe, it, expect = t.describe, t.it, t.expect" in source or "local it, expect = t.it, t.expect" in source or "local expect = t.expect" in source
    source = source.replace("local describe, it, expect = t.describe, t.it, t.expect", "local expect = t.expect").replace("local it, expect = t.it, t.expect", "local expect = t.expect")
    data = source.encode()
    masked = bytearray(data)
    original_tree = PARSER.parse(data)
    strings = [(node.start_byte, node.end_byte) for node in walk(original_tree.root_node) if node.type in {"string", "comment"}]
    for match in re.finditer(rb"\btypeof\s*\(", data):
        if any(start <= match.start() < end for start, end in strings):
            continue
        depth, end = 1, match.end()
        while end < len(data) and depth:
            depth += (data[end] == 40) - (data[end] == 41)
            end += 1
        if depth == 0:
            masked[match.start():end] = b"any" + bytes(10 if char == 10 else 32 for char in data[match.start() + 3:end])
    for match in re.finditer(rb"\btype\s+\w+\s*=\s*<[^\n]+", data):
        masked[match.start():match.end()] = b" " * (match.end() - match.start())
    tree = PARSER.parse(bytes(masked))
    edits = []
    counts = collections.Counter()
    calls = [node for node in walk(tree.root_node) if node.type == "function_call"]
    suites = [node for node in calls if node.children[0].text == b"t.describe" or (aliased and node.children[0].text == b"describe")]
    imports = [node for node in tree.root_node.named_children if node.type == "variable_declaration" and b'require("./lib/testkit")' in node.text]
    if not imports:
        return source, counts
    if len(imports) != 1 or not re.fullmatch(rb'local\s+t\s*=\s*require\("\./lib/testkit"\)', imports[0].text):
        raise ValueError(f"{spec}: unsupported harness binding")
    edits.append((imports[0].start_byte, imports[0].end_byte, b""))
    for node in calls:
        target = node.children[0]
        args = arguments(node)
        name = target.text.decode()
        if name == "t.describe" or (aliased and name == "describe"):
            edits.append((target.start_byte, target.end_byte, b"verifyHarness:suite"))
            counts["suites"] += 1
        elif name == "t.it" or (aliased and name == "it"):
            if len(args) not in (2, 3) or args[1].type != "function_definition":
                raise ValueError(f"{spec}: unsupported case at {node.start_point}")
            enclosing = [suite for suite in suites if suite.start_byte < node.start_byte < suite.end_byte]
            if not enclosing:
                following = [suite for suite in suites if suite.start_byte > node.start_byte]
                if not following:
                    raise ValueError(f"{spec}: case has no suite")
                enclosing = [min(following, key=lambda item: item.start_byte)]
                counts["helper_registrations"] += 1
            suite = max(enclosing, key=lambda item: item.start_byte)
            suite_name = arguments(suite)[0]
            options = {}
            if len(args) == 3:
                if args[2].type != "table_constructor":
                    raise ValueError(f"{spec}: computed case options")
                for field in args[2].named_children:
                    key = field.child_by_field_name("name")
                    value = field.child_by_field_name("value")
                    if key is None or value is None or key.text.decode() not in {"id", "tier"}:
                        raise ValueError(f"{spec}: unsupported case option")
                    options[key.text.decode()] = value
            if "id" in options:
                case_id = options["id"].text
            elif literal(suite_name) is not None and literal(args[0]) is not None:
                case_id = json.dumps(f"{spec}::{literal(suite_name)}::{literal(args[0])}", ensure_ascii=False).encode()
            else:
                case_id = json.dumps(spec + "::").encode() + b" .. " + suite_name.text + b' .. "::" .. ' + args[0].text
            edits.append((target.start_byte, target.end_byte, b"verifyHarness:case"))
            edits.append((args[1].start_byte, args[1].start_byte, b"{ id = " + case_id + b", run = "))
            edits.append((args[1].end_byte, args[1].end_byte, b" }"))
            if len(args) == 3:
                edits.append((args[1].end_byte, args[2].end_byte, b""))
            if "tier" in options:
                gate = literal(options["tier"])
                if gate not in {"full", "release"}:
                    raise ValueError(f"{spec}: unsupported tier")
                parameters = next(child for child in args[1].children if child.type == "parameters")
                edits.append((parameters.start_byte, parameters.end_byte, b"(context)"))
                allowed = 'tier == "release"' if gate == "release" else 'tier == "full" or tier == "release"'
                edits.append((parameters.end_byte, parameters.end_byte, f'\nif not ({allowed}) then context:skip("tier:{gate}") end\n'.encode()))
                counts["tier_guards"] += 1
            counts["cases"] += 1
        elif name == "t.expect" or (aliased and name == "expect"):
            if name == "t.expect":
                edits.append((target.start_byte, target.end_byte, b"Verify.expect"))
            if len(args) == 1 and args[0].type == "function_call":
                edits.append((args[0].start_byte, args[0].start_byte, b"("))
                edits.append((args[0].end_byte, args[0].end_byte, b")"))
                counts["single_return_arguments"] += 1
        elif target.type == "dot_index_expression":
            field = target.child_by_field_name("field")
            field_name = field.text.decode()
            table = target.child_by_field_name("table")
            if field_name in MATCHERS:
                dot = data.rfind(b".", table.end_byte, field.start_byte)
                if dot < 0:
                    raise ValueError(f"{spec}: missing matcher operator")
                edits.append((dot, dot + 1, b":"))
                counts["matchers"] += 1
                if field_name == "toBeCloseTo" and len(args) == 1:
                    edits.append((args[0].end_byte, args[0].end_byte, b", 1e-4"))
                    counts["explicit_tolerances"] += 1
            elif field_name == "never":
                if args:
                    raise ValueError(f"{spec}: negation takes arguments")
                edits.append((node.children[1].start_byte, node.children[1].end_byte, b""))
                counts["negations"] += 1
    for node in walk(tree.root_node):
        if node.type == "return_statement" and node.text.strip() == b"return t":
            edits.append((node.start_byte, node.end_byte, b"return nil"))
            counts["removed_harness_returns"] += 1
        if node.type == "dot_index_expression" and node.text == b"t.expect" and node.parent.type != "function_call":
            edits.append((node.start_byte, node.end_byte, b"Verify.expect"))
    spans = sorted((start, end) for start, end, _ in edits if start != end)
    if any(left[1] > right[0] for left, right in zip(spans, spans[1:])):
        raise ValueError(f"{spec}: overlapping edits")
    for start, end, replacement in sorted(edits, key=lambda item: (item[0], item[1]), reverse=True):
        data = data[:start] + replacement + data[end:]
    body = data.decode().removeprefix("--!strict").lstrip("\n")
    if spec == "native_gallery_shell":
        body = body.replace("function expectDevice(width, height, display, input)", "function expectDevice(width, height: number, display, input)")
        counts["numeric_parameter_annotations"] += 1
    result = '--!strict\nlocal Verify = require("../tools/vendor/verify/src/core")\n\nreturn function(verifyHarness: Verify.Harness, tier: string)\n' + body.rstrip() + '\nend\n'
    return result, counts


def main():
    parser = argparse.ArgumentParser(description="Convert Facet testkit specs to Verify registrations with stable case IDs.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true", help="Check that current specs equal the formatted transformation.")
    parser.add_argument("--revision", help="Read the original specs from this Git revision.")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    records = []
    converted = {}
    for path in sorted((args.root / "tests").glob("*.spec.luau")):
        source = subprocess.check_output(["git", "show", f"{args.revision}:{path.relative_to(args.root).as_posix()}"], cwd=args.root).decode() if args.revision else path.read_text()
        result, counts = transform(source, path.name[:-10])
        if args.check or args.write:
            for _ in range(5):
                formatted = subprocess.run(["stylua", "-"], input=result, text=True, capture_output=True, check=True).stdout
                if formatted == result:
                    break
                result = formatted
            else:
                raise ValueError(f"{path}: formatting did not stabilize")
        if args.check:
            if path.read_text() != result:
                raise ValueError(f"{path}: current bytes differ from the codemod output")
        if source != result:
            records.append({"path": path.relative_to(args.root).as_posix(), **counts})
            converted[path] = result
    if args.write:
        for path, result in converted.items():
            path.write_text(result)
    totals = collections.Counter()
    for record in records:
        totals.update({key: value for key, value in record.items() if key != "path"})
    receipt = {"schema": "facet-verify-codemod/1", "files": records, "totals": dict(totals)}
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"files": len(records), **totals}))


if __name__ == "__main__":
    main()
