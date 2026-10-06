#!/usr/bin/env python3
from functools import lru_cache
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from strip_comments import LuauScanner

EXTERNAL = ("@lune/", "@std/")
REQUIRES = re.compile(r'\brequire\s*\(?\s*(["\'])([^"\']+)\1\s*(\.\.)?')


def resolve(path, requested):
    dynamic = requested.startswith("dynamic:")
    requested = requested.removeprefix("dynamic:")
    if requested.startswith(EXTERNAL):
        return None
    if requested.startswith("@self/"):
        base = path.parent / requested.removeprefix("@self/") if path.name == "init.luau" else path.with_suffix("") / requested.removeprefix("@self/")
    elif requested.startswith("."):
        base = (path.parent.parent if path.name == "init.luau" else path.parent) / requested
    else:
        return False
    if dynamic and (base.is_dir() or any(base.parent.glob(base.name + "*.luau"))):
        return None
    if requested.endswith("/") and base.is_dir():
        return None
    for candidate in (base.with_suffix(base.suffix + ".luau"), base.with_suffix(base.suffix + ".lua"), base / "init.luau"):
        if candidate.is_file():
            return candidate.resolve()
    return False


@lru_cache(maxsize=None)
def imports(path):
    class ImportScanner(LuauScanner):
        def __init__(self, source):
            super().__init__(source)
            self.strings = []

        def quoted(self, index):
            end = super().quoted(index)
            self.strings.append((index, end))
            return end

        def interpolated(self, index):
            start = index
            index += 1
            while index < len(self.source):
                char = self.source[index]
                if char == "\\":
                    index += 2
                elif char == "`":
                    self.strings.append((start, index + 1))
                    return index + 1
                elif char == "{":
                    self.strings.append((start, index + 1))
                    index = self.code(index + 1, interpolation=True)
                    start = index - 1
                else:
                    index += 1
            raise ValueError("unterminated Luau interpolated string")

    source = path.read_text()
    scanner = ImportScanner(source)
    scanner.code()
    ignored = scanner.comments + scanner.strings + [(start, end) for start, end, _, _ in scanner.long_strings]
    erased = []
    for expression in re.finditer(r"\btypeof\s*\(", source):
        if any(start <= expression.start() < end for start, end in ignored):
            continue
        prefix = source[:expression.start()]
        if re.search(r"(?:^|\n)\s*(?:local\s+)?[\w.,]+(?:\s*:\s*[^=\n]*)?\s*=\s*$", prefix) or re.search(r"\breturn\s*$", prefix):
            continue
        depth, index = 1, expression.end()
        while index < len(source) and depth:
            region = next((end for start, end in ignored if start <= index < end), None)
            if region is not None:
                index = region
                continue
            depth += (source[index] == "(") - (source[index] == ")")
            index += 1
        if depth == 0:
            erased.append((expression.start(), index))
    ignored.extend(erased)
    aliases = {"require"}
    for binding in re.finditer(r"\blocal\s+(\w+)\s*=\s*require\s*::", source):
        if not any(start <= binding.start() < end for start, end in ignored):
            aliases.add(binding[1])
    calls = re.compile(r"\b(?:" + "|".join(re.escape(name) for name in sorted(aliases)) + r")\s*\(?\s*([\"'])([^\"']+)\1\s*(\.\.)?")
    return [("dynamic:" if match[3] else "") + match[2] for match in calls.finditer(source) if not any(start <= match.start() < end for start, end in ignored)]

def missing_dependencies(path, visited=None):
    visited = visited or set()
    path = path.resolve()
    if path in visited:
        return []
    visited.add(path)
    missing = []
    for requested in imports(path):
        resolved = resolve(path, requested)
        if resolved is False:
            missing.append(f"{path.relative_to(ROOT)}: {requested}")
        elif resolved is not None and "vendor/compose" not in str(resolved):
            missing.extend(missing_dependencies(resolved, visited))
    return sorted(set(missing))


def architecture():
    failures = []
    for folder in ("src", "examples", "bench"):
        for path in sorted((ROOT / folder).rglob("*.luau")):
            if "vendor/compose" in str(path):
                continue
            failures.extend(missing_dependencies(path))
            text = path.read_text()
            if re.search(r"\bFacet\.(new|createHost|newPresenter|newActionSystem|newFocusGraph)\s*\(", text):
                failures.append(f"{path.relative_to(ROOT)}: removed Facet scaffolding API")
            if re.search(r"\blocal\s+H\s*=\s*[^\n]*constructors", text):
                failures.append(f"{path.relative_to(ROOT)}: use Host for Roblox constructors")
    for folder in ("examples", "bench"):
        for path in sorted((ROOT / folder).rglob("*.luau")):
            for requested in imports(path):
                target = resolve(path, requested)
                if isinstance(target, Path) and target.is_relative_to(ROOT / "src") and target != ROOT / "src/init.luau":
                    failures.append(f"{path.relative_to(ROOT)}: requires private Facet module {target.relative_to(ROOT)}")
    vendor = ROOT / "src/vendor"
    if vendor.exists():
        failures.extend(f"src/vendor/{path.name}: unapproved vendor" for path in vendor.iterdir() if path.name != "compose")
    for removed in ("src/client/application.luau", "src/render/compose_scene.luau", "src/render/renderer.luau", "src/core/services.luau"):
        if (ROOT / removed).exists():
            failures.append(f"{removed}: removed architecture still exists")
    return sorted(set(failures))


def main():
    failures = architecture()
    print(f"architecture: {len(failures)} findings")
    for finding in failures:
        print(f"  {finding}")
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
