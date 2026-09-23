#!/usr/bin/env python3

import argparse
import ast
import io
from pathlib import Path
import re
import subprocess
import sys
import tokenize


ROOT = Path(__file__).resolve().parents[1]
SUFFIXES = {".luau", ".lua", ".py", ".sh"}
LEGAL = re.compile(
    r"Copyright\s+(?:\(c\)|\d{4})|SPDX-License-Identifier:|Permission is hereby granted|"
    r"Licensed under the|Licence and required notices:",
    re.IGNORECASE,
)
DIRECTIVE = re.compile(
    r"^(?:--!(?:strict|nonstrict|nocheck|native|optimize|nolint)\b|"
    r"--\s*(?:stylua:|selene:|luacheck:|theme_sync:(?:begin|end)\b)|"
    r"#!|#\s*(?:shellcheck\b|shfmt:|fmt:|isort:|noqa\b|type:|pyright:|"
    r"mypy:|ruff:|pylint:|pragma:\s*no cover|.*coding[:=]))"
)
LONG_OPEN = re.compile(r"\[(=*)\[")


def apply_edits(source, edits):
    previous = len(source) + 1
    for start, end, replacement in sorted(edits, reverse=True):
        if end > previous:
            raise ValueError("overlapping source edits")
        source = source[:start] + replacement + source[end:]
        previous = start
    return source


def comment_edits(source, spans):
    protected = set()
    for index, (start, end) in enumerate(spans):
        if LEGAL.search(source[start:end]):
            protected.add(index)
            if "Licence and required notices:" in source[start:end]:
                for before in range(index - 1, max(-1, index - 4), -1):
                    if source[spans[before][1]:spans[before + 1][0]].strip():
                        break
                    protected.add(before)
                continue
            before = index - 1
            while before >= 0 and source[spans[before][1]:spans[before + 1][0]].strip() == "":
                if source[spans[before][1]:spans[before + 1][0]].count("\n") > 1:
                    break
                protected.add(before)
                before -= 1
            after = index + 1
            while after < len(spans) and source[spans[after - 1][1]:spans[after][0]].strip() == "":
                if source[spans[after - 1][1]:spans[after][0]].count("\n") > 1:
                    break
                protected.add(after)
                after += 1
    edits = []
    for index, (start, end) in enumerate(spans):
        if index in protected or DIRECTIVE.match(source[start:end]):
            continue
        line_start = source.rfind("\n", 0, start) + 1
        if not source[line_start:start].strip():
            start = line_start
        elif end == len(source) or source[end] in "\r\n":
            leading = start
            while leading > line_start and source[leading - 1] in " \t":
                leading -= 1
            if leading == line_start or source[leading - 1] != "\\":
                start = leading
        removed = source[start:end]
        replacement = "".join(char for char in removed if char in "\r\n")
        if end < len(source) and source[end] not in "\r\n" and not replacement:
            replacement = " "
        edits.append((start, end, replacement))
    return edits


class LuauScanner:
    def __init__(self, source):
        self.source = source
        self.comments = []
        self.long_strings = []

    def quoted(self, index):
        quote = self.source[index]
        index += 1
        while index < len(self.source):
            if self.source[index] == "\\":
                index += 2
            elif self.source[index] == quote:
                return index + 1
            else:
                index += 1
        raise ValueError("unterminated Luau quoted string")

    def long(self, opened):
        closer = "]" + opened.group(1) + "]"
        end = self.source.find(closer, opened.end())
        if end < 0:
            raise ValueError("unterminated Luau long bracket")
        return end + len(closer)

    def interpolated(self, index):
        index += 1
        while index < len(self.source):
            char = self.source[index]
            if char == "\\":
                index += 2
            elif char == "`":
                return index + 1
            elif char == "{":
                index = self.code(index + 1, interpolation=True)
            else:
                index += 1
        raise ValueError("unterminated Luau interpolated string")

    def code(self, index=0, interpolation=False):
        depth = 0
        while index < len(self.source):
            char = self.source[index]
            if self.source.startswith("--", index):
                opened = LONG_OPEN.match(self.source, index + 2)
                end = self.long(opened) if opened else self.source.find("\n", index)
                end = len(self.source) if end < 0 else end
                self.comments.append((index, end))
                index = end
            elif char in "\"'":
                index = self.quoted(index)
            elif char == "`":
                index = self.interpolated(index)
            elif char == "[" and (opened := LONG_OPEN.match(self.source, index)):
                end = self.long(opened)
                self.long_strings.append((index, end, opened.end(), end - len(opened.group(1)) - 2))
                index = end
            elif interpolation and char == "}" and depth == 0:
                return index + 1
            else:
                if char == "{":
                    depth += 1
                elif char == "}":
                    depth -= 1
                index += 1
        if interpolation:
            raise ValueError("unterminated Luau interpolation expression")
        return index


def strip_luau(source):
    scanner = LuauScanner(source)
    scanner.code()
    return apply_edits(source, comment_edits(source, scanner.comments))


class ShellScanner:
    def __init__(self, source):
        self.source = source
        self.comments = []

    def single_quote(self, index, escaped=False):
        index += 1
        while index < len(self.source):
            if escaped and self.source[index] == "\\":
                index += 2
            elif self.source[index] == "'":
                return index + 1
            else:
                index += 1
        raise ValueError("unterminated shell single quote")

    def double_quote(self, index):
        index += 1
        while index < len(self.source):
            if self.source[index] == "\\":
                index += 2
            elif self.source[index] == '"':
                return index + 1
            else:
                expanded = self.expansion(index)
                index = expanded if expanded is not None else index + 1
        raise ValueError("unterminated shell double quote")

    def balanced(self, index, opener, closer):
        depth = 1
        while index < len(self.source):
            char = self.source[index]
            if char == "\\":
                index += 2
            elif char == "'":
                index = self.single_quote(index)
            elif char == '"':
                index = self.double_quote(index)
            elif (expanded := self.expansion(index)) is not None:
                index = expanded
            elif char == closer:
                depth -= 1
                index += 1
                if depth == 0:
                    return index
            else:
                depth += char == opener
                index += 1
        raise ValueError("unterminated shell expansion")

    def expansion(self, index):
        if self.source.startswith("$((", index):
            return self.balanced(index + 2, "(", ")")
        if self.source.startswith("$(", index):
            return self.code(index + 2, ")")
        if self.source.startswith("${", index):
            return self.balanced(index + 2, "{", "}")
        if self.source.startswith("$'", index):
            return self.single_quote(index + 1, escaped=True)
        if self.source[index] == "`":
            return self.code(index + 1, "`")
        return None

    def heredoc(self, index):
        strip_tabs = self.source[index:index + 1] == "-"
        index += strip_tabs
        while self.source[index:index + 1] in (" ", "\t"):
            index += 1
        delimiter = []
        while index < len(self.source) and self.source[index] not in " \t\r\n;|&()<>":
            char = self.source[index]
            if char in "\"'":
                end = self.source.find(char, index + 1)
                if end < 0:
                    raise ValueError("unterminated heredoc delimiter")
                delimiter.append(self.source[index + 1:end])
                index = end + 1
            elif char == "\\":
                delimiter.append(self.source[index + 1:index + 2])
                index += 2
            else:
                delimiter.append(char)
                index += 1
        if not delimiter:
            raise ValueError("missing heredoc delimiter")
        return index, ("".join(delimiter), strip_tabs)

    def skip_heredocs(self, index, pending):
        for delimiter, strip_tabs in pending:
            while index < len(self.source):
                end = self.source.find("\n", index)
                end = len(self.source) if end < 0 else end + 1
                line = self.source[index:end].rstrip("\r\n")
                if strip_tabs:
                    line = line.lstrip("\t")
                index = end
                if line == delimiter:
                    break
            else:
                raise ValueError("unterminated shell heredoc")
        return index

    def code(self, index=0, terminator=None):
        word_start = True
        pending = []
        depth = 0
        while index < len(self.source):
            char = self.source[index]
            if terminator and char == terminator and depth == 0:
                return index + 1
            if char == "#" and word_start:
                end = self.source.find("\n", index)
                end = len(self.source) if end < 0 else end
                self.comments.append((index, end))
                index = end
            elif char == "\\":
                if self.source[index + 1:index + 2] != "\n":
                    word_start = False
                index += 2
            elif char == "'":
                index = self.single_quote(index)
                word_start = False
            elif char == '"':
                index = self.double_quote(index)
                word_start = False
            elif (expanded := self.expansion(index)) is not None:
                index = expanded
                word_start = False
            elif self.source.startswith("((", index):
                index = self.balanced(index + 1, "(", ")")
                word_start = True
            elif self.source.startswith("<<<", index):
                index += 3
                word_start = True
            elif self.source.startswith("<<", index):
                index, heredoc = self.heredoc(index + 2)
                pending.append(heredoc)
                word_start = True
            elif char == "\n":
                index = self.skip_heredocs(index + 1, pending)
                pending.clear()
                word_start = True
            else:
                if terminator == ")":
                    if char == "(":
                        depth += 1
                    elif char == ")" and depth:
                        depth -= 1
                word_start = char in " \t\r;|&()<>"
                index += 1
        if terminator or pending:
            raise ValueError("unterminated shell command substitution or heredoc")
        return index


def strip_shell(source):
    scanner = ShellScanner(source)
    scanner.code()
    result = apply_edits(source, comment_edits(source, scanner.comments))
    checked = subprocess.run(["bash", "-n"], input=result, text=True, capture_output=True)
    if checked.returncode:
        raise ValueError(checked.stderr.strip())
    return result


class PythonPositions:
    def __init__(self, source):
        self.lines = source.splitlines(keepends=True)
        self.offsets = [0]
        for line in self.lines:
            self.offsets.append(self.offsets[-1] + len(line))

    def token(self, point):
        return self.offsets[point[0] - 1] + point[1]

    def node_point(self, row, column):
        return self.offsets[row - 1] + len(self.lines[row - 1].encode()[:column].decode())

    def node(self, node):
        return (
            self.node_point(node.lineno, node.col_offset),
            self.node_point(node.end_lineno, node.end_col_offset),
        )


def trim_python_whitespace(source):
    positions = PythonPositions(source)
    protected = [
        (positions.token(token.start), positions.token(token.end))
        for token in tokenize.generate_tokens(io.StringIO(source).readline)
        if token.type == tokenize.STRING
    ]
    protected.extend(
        positions.node(node)
        for node in ast.walk(ast.parse(source))
        if isinstance(node, ast.JoinedStr)
    )
    return apply_edits(source, [
        (match.start(), match.end(), "")
        for match in re.finditer(r"[ \t]+(?=\r?$)", source, re.MULTILINE)
        if not any(start < match.end() and end > match.start() for start, end in protected)
    ])


def strip_python(source):
    tree = ast.parse(source)
    positions = PythonPositions(source)
    tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    comments = [(positions.token(token.start), positions.token(token.end))
                for token in tokens if token.type == tokenize.COMMENT]
    edits = comment_edits(source, comments)
    module_doc = tree.body[0] if ast.get_docstring(tree, clean=False) is not None else None
    references = [node for node in ast.walk(tree) if isinstance(node, ast.Name) and node.id == "__doc__"]
    preserve_help = bool(module_doc and references)
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        value = ast.get_docstring(node, clean=False)
        if value is None or LEGAL.search(value):
            continue
        doc = node.body[0]
        start, end = positions.node(doc)
        replacement = "pass" if len(node.body) == 1 and not isinstance(node, ast.Module) else ""
        after_doc = end
        while source[after_doc:after_doc + 1] in (" ", "\t"):
            after_doc += 1
        if not replacement and source[after_doc:after_doc + 1] == ";":
            end = after_doc + 1
            while source[end:end + 1] in (" ", "\t"):
                end += 1
        edits.append((start, end, replacement))
    if preserve_help:
        if any(isinstance(node, ast.Name) and node.id == "CLI_HELP" for node in ast.walk(tree)):
            raise ValueError("CLI_HELP already exists; move __doc__ references explicitly")
        start, end = positions.node(module_doc)
        literal = source[start:end]
        futures = [node for node in tree.body if isinstance(node, ast.ImportFrom) and node.module == "__future__"]
        if futures:
            _, insert_at = positions.node(futures[-1])
            insert_at = source.find("\n", insert_at)
            insert_at = len(source) if insert_at < 0 else insert_at + 1
            edits.append((insert_at, insert_at, "CLI_HELP = " + literal + "\n"))
        else:
            edits = [edit for edit in edits if edit[0] != start]
            edits.append((start, end, "CLI_HELP = " + literal))
        for node in references:
            start, end = positions.node(node)
            edits.append((start, end, "CLI_HELP"))
    result = trim_python_whitespace(apply_edits(source, edits))
    ast.parse(result)
    return result


def strip_templates(source, path):
    if path.as_posix().endswith("tools/lune/scaffold.luau"):
        scanner = LuauScanner(source)
        scanner.code()
        edits = []
        for start, _, content_start, content_end in scanner.long_strings:
            declaration = re.search(r"local\s+(\w+_TEMPLATE)\s*=\s*$", source[:start])
            if declaration and declaration.group(1) not in {"API_STUB_TEMPLATE", "LEDGER_ROW_TEMPLATE", "GUIDE_CATALOG_ROW_TEMPLATE"}:
                value = source[content_start:content_end]
                edits.append((content_start, content_end, strip_luau(value)))
        return apply_edits(source, edits)
    if path.as_posix().endswith("tools/build_word_lists.py"):
        tree = ast.parse(source)
        positions = PythonPositions(source)
        edits = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.startswith("--!strict\n"):
                start, end = positions.node(node)
                edits.append((start, end, repr(strip_luau(node.value))))
        return apply_edits(source, edits)
    return source


def transform(source, path):
    source = strip_templates(source, path)
    if path.suffix in {".lua", ".luau"}:
        return strip_luau(source)
    if path.suffix == ".py":
        return strip_python(source)
    if path.suffix == ".sh":
        return strip_shell(source)
    return source


def source_paths(root, selections):
    found = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *selections],
        check=True, capture_output=True,
    ).stdout.decode().split("\0")
    for relative in sorted(set(found)):
        path = Path(relative)
        if path.suffix in SUFFIXES and "vendor" not in path.parts and (root / path).is_file():
            yield path


def main():
    parser = argparse.ArgumentParser(description="Remove first-party source comments while preserving executable directives and literals.")
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--write", action="store_true")
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--dry-run", action="store_true")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    changes = []
    try:
        for path in source_paths(args.root, args.paths):
            with (args.root / path).open(encoding="utf-8", newline="") as handle:
                original = handle.read()
            updated = transform(original, path)
            if updated != original:
                changes.append((path, updated))
    except (ValueError, SyntaxError, tokenize.TokenError) as error:
        print(f"strip_comments: {path}: {error}", file=sys.stderr)
        return 2
    for path, updated in changes:
        print(path)
        if args.write:
            with (args.root / path).open("w", encoding="utf-8", newline="") as handle:
                handle.write(updated)
    print(f"strip_comments: {len(changes)} file(s) {'updated' if args.write else 'need changes'}", file=sys.stderr)
    return int(args.check and bool(changes))


if __name__ == "__main__":
    raise SystemExit(main())
