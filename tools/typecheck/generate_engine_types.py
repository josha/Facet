#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CLASSES = sorted(set('Camera CanvasGroup Folder Frame GuiObject GuiButton ImageButton ImageLabel InputAction InputBinding InputContext Path2D ScrollingFrame ScreenGui BillboardGui SurfaceGui StyleRule StyleSheet TextBox TextButton TextLabel UIAspectRatioConstraint UICorner UIDragDetector UIFlexItem UIGradient UIGridLayout UIListLayout UIPadding UIPageLayout UIScale UIShadow UISizeConstraint UIStroke UITextSizeConstraint ViewportFrame WorldModel'.split()))

CLASSES_SET = set(CLASSES)


def records(source):
    return {
        match[1]: {
            'parent': match[2],
            'fields': dict(re.findall(r'^\t([A-Za-z_]\w*): ([^\n]+)$', match[3], re.MULTILINE)),
        }
        for match in re.finditer(r'^declare extern type (\w+)(?: extends (\w+))? with\n(.*?)^end$', source, re.MULTILINE | re.DOTALL)
    }


def metadata(root, classes):
    result = {}
    for name in classes:
        path = root / 'content/en-us/reference/engine/classes' / (name + '.yaml')
        content = path.read_text()
        section = re.search(r'^properties:\n(.*?)(?=^\S|\Z)', content, re.MULTILINE | re.DOTALL)
        writable = []
        if section:
            for entry in re.split(r'(?=^  - name: )', section[1], flags=re.MULTILINE):
                member = re.search(r'^  - name: \w+\.(\w+)\s*$', entry, re.MULTILINE)
                if not member:
                    continue
                write = re.search(r'^      write: (\S+)', entry, re.MULTILINE)
                readonly = re.search(r'^      - ReadOnly\s*$', entry, re.MULTILINE)
                if not readonly and write and write[1] == 'None':
                    writable.append(member[1])
        result[name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'writable': sorted(writable)}
    return result


def native_type(value):
    value = re.sub(r'\bEnum(?!Item\b)([A-Z]\w*)', r'Enum.\1', value)
    value = re.sub(r'\bContentId\b', 'string', value)
    return re.sub(r'\bany\b', 'unknown', value)


def generate(definitions, schema):
    entries = records(definitions)
    ordered = []
    def visit(name):
        if name in ordered:
            return
        parent = entries[name]['parent']
        if parent:
            visit(parent)
        ordered.append(name)
    for name in CLASSES:
        visit(name)
    result = ['--!strict', 'local Compose = require("../vendor/compose/core")', '', 'export type Value<T> = T | Compose.Readable<T> | Compose.Formula<T> | Compose.Body<T>', 'export type StaticValue = typeof(Compose.static(nil))', 'export type Constructor<P, N> = ((P) -> N) & ((string) -> (P) -> N)', 'export type AttributeValue = string | boolean | number | UDim | UDim2 | BrickColor | Color3 | Vector2 | Vector3 | CFrame | NumberSequence | ColorSequence | NumberRange | Rect | Font', 'export type Attributes = { [string]: Value<AttributeValue?> }', '']
    aliases = {}
    def shared(native):
        if native not in aliases:
            name = 'Value' + ''.join(part[:1].upper() + part[1:] for part in re.findall(r'[A-Za-z0-9]+', native.replace('?', ' Optional ')))
            assert name not in aliases.values(), name
            aliases[native] = name
        return aliases[native]
    def is_instance(name):
        while name in entries:
            if name == 'Instance':
                return True
            name = entries[name]['parent']
        return False
    own = {}
    for name in ordered:
        parent = entries[name]['parent']
        fields = ['\tAttributes: Attributes?,'] if name == 'Instance' else []
        for key, native in entries[name]['fields'].items():
            if native.startswith('RBXScriptSignal<'):
                arguments = native[len('RBXScriptSignal<'):-1]
                if arguments.startswith('(') and arguments.endswith(')'):
                    arguments = arguments[1:-1]
                arguments = re.sub(r'\bEnum(?!Item\b)([A-Z]\w*)', r'Enum.\1', arguments)
                if re.search(r'\bany\b', arguments):
                    arguments = re.sub(r'\bany\b', 'unknown', arguments)
                fields.append(f'\t{key}: (({arguments}) -> ())?,')
            elif key in schema[name]['writable']:
                value = shared(native_type(native))
                if any(is_instance(word) for word in re.findall(r'\b\w+\b', native)):
                    value = '(' + value + ' | StaticValue)'
                fields.append(f'\t{key}: {value}?,')
        own[name] = (own[parent] if parent else []) + fields
        if name not in CLASSES_SET:
            continue
        result += [f'export type {name}NativeProps = {{', *own[name], '\t[number]: Compose.Child,', '}', f'export type {name}Props = {{', *own[name], '\t[number]: Compose.Child,', f'\tref: (({name}) -> ())?,', '}', '']
    shared_lines = [f'export type {alias} = Value<{native}>' for native, alias in sorted(aliases.items(), key=lambda item: item[1])]
    insert_at = result.index('export type Attributes = { [string]: Value<AttributeValue?> }') + 1
    result[insert_at:insert_at] = shared_lines
    datatypes = 'UDim UDim2 Vector2 Vector3 Color3 CFrame Enum Font Rect ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange Path2DControlPoint FloatCurveKey TweenInfo'.split()
    result += ['export type RobloxTypes = {', *[f'\t{name}: typeof({name}),' for name in datatypes], '\tBrickColor: typeof(BrickColor)?,', '}', '']
    observed = set('AbsoluteContentSize AbsolutePosition AbsoluteSize AbsoluteWindowSize CanvasPosition CurrentPage DisplayImage DisplayName Enabled FontFace GamepadEnabled GuiState Interactable KeyCode KeyboardEnabled MouseEnabled Parent Position PreferredBinding PreferredInput PreferredTransparency PrimaryModifier ReducedMotionEnabled SecondaryModifier SelectedObject Size Text TextBounds TextFits TextSize TextColor3 TextXAlignment TextYAlignment TextWrapped RichText TextScaled TextTruncate LineHeight TouchEnabled Visible OnScreenKeyboardVisible OnScreenKeyboardSize AbsoluteCanvasSize Scale CursorPosition'.split())
    groups = {}
    observed_classes = set('GuiBase2d GuiObject GuiService UserInputService LayerCollector Instance InputAction InputBinding InputContext TextLabel TextBox TextButton ScrollingFrame UIGridStyleLayout UIPageLayout UIScale'.split())
    for name, entry in sorted(entries.items()):
        if name not in observed_classes:
            continue
        for key, native in entry['fields'].items():
            if key in observed and not native.startswith('RBXScriptSignal'):
                groups.setdefault((native_type(native), name), []).append(key)
    merged = {}
    for (native, name), keys in groups.items():
        merged.setdefault((native, tuple(sorted(keys))), []).append(name)
    observations = []
    for (native, keys), names in sorted(merged.items(), key=lambda item: (sorted(item[1])[0], item[0][0])):
        owner = ' | '.join(sorted(names))
        members = ' | '.join(f'\"{key}\"' for key in keys)
        observations.append(f'(({owner}, {members}) -> Compose.Cell<{native}>)')
    result += ['export type Observe = ' + '\n\t& '.join(observations), '']
    result += ['export type Host = {']
    for name in CLASSES:
        if name in {'GuiObject', 'GuiButton'}:
            continue
        result.append(f'\t{name}: Constructor<{name}NativeProps, {name}>,')
    result += ['}', '', 'return {}', '']
    formatted = '\n'.join(result)
    for _ in range(2):
        formatted = subprocess.run(['stylua', '-'], input=formatted, text=True, capture_output=True, check=True).stdout
    return formatted, ordered


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--definitions', type=Path, default=ROOT / 'artifacts/verify/types/roblox.d.luau')
    parser.add_argument('--creator-docs', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    definitions = args.definitions.read_text()
    parsed = records(definitions)
    classes = set()
    for name in CLASSES:
        while name:
            classes.add(name)
            name = parsed[name]['parent']
    schema_path = ROOT / 'tools/typecheck/engine_members.json'
    if args.creator_docs:
        schema = metadata(args.creator_docs, sorted(classes))
        schema_path.write_text(json.dumps(schema, indent=2) + '\n')
    else:
        schema = json.loads(schema_path.read_text())
    result, _ = generate(definitions, schema)
    output = ROOT / 'src/ui/engine_types.luau'
    if args.check:
        if output.read_text() != result:
            raise SystemExit('engine_types.luau differs; run tools/typecheck/generate_engine_types.py')
        print('native engine types match pinned declarations and writable metadata')
    else:
        output.write_text(result)


if __name__ == '__main__':
    main()
