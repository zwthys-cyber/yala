#!/usr/bin/env python3
"""Generate typed legacy UI-copy adapters from the application's ARB files."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'lib/l10n/ui_copy_catalog.g.dart'


def dart_string(value):
    return json.dumps(value, ensure_ascii=False).replace('$', r'\$')


def generate():
    data = json.loads((ROOT / 'lib/l10n/app_en.arb').read_text())
    exact, patterns, seen = [], [], set()
    items = sorted(data.items(), key=lambda item: 0 if item[0].startswith('uiLegacy') else 1)
    for key, value in items:
        if key.startswith('@') or not isinstance(value, str) or value in seen:
            continue
        placeholders = list(dict.fromkeys(re.findall(r'\{(\w+)\}', value)))
        residue = re.sub(r'\{\w+\}', '', value)
        if '{' in residue or '}' in residue:
            continue  # ICU plurals/selects remain with their existing callers.
        if not placeholders:
            exact.append(f'    {dart_string(value)}: l10n.{key},')
            seen.add(value)
            continue
        metadata = data.get('@' + key, {}).get('placeholders', {})
        args, prelude = [], []
        supported = True
        for index, name in enumerate(placeholders):
            kind = metadata.get(name, {}).get('type', 'Object')
            arg = f'args[{index}]'
            if kind in ('int', 'double', 'num'):
                prelude.append(f'      final value{index} = {kind}.tryParse({arg});')
                prelude.append(f'      if (value{index} == null) return null;')
                arg = f'value{index}'
            elif kind not in ('String', 'Object', 'Object?'):
                supported = False
                break
            args.append(arg)
        if not supported:
            continue
        # Getter parameter order follows ARB placeholder metadata, which can
        # differ from its order in the English sentence.
        ordered_names = list(metadata) if metadata else placeholders
        if set(ordered_names) != set(placeholders):
            continue
        ordered_args = [args[placeholders.index(name)] for name in ordered_names]
        description = data.get('@' + key, {}).get('description', '')
        keyword_match = re.search(r'UI keywords: ([\w,]+)', description)
        keywords = set(keyword_match[1].split(',')) if keyword_match else set()
        ordered_args = [
            f'_localizeUiKeyword(l10n, {arg})' if name in keywords else arg
            for name, arg in zip(ordered_names, ordered_args)
        ]
        line = f'      return l10n.{key}({", ".join(ordered_args)});'
        priority = 2 if keywords else 1 if key.startswith('uiLegacy') else 0
        end = f'    }}, priority: {priority}),' if priority else '    }),'
        patterns += [f'    _UiCopyRule({dart_string(value)}, (args) {{', *prelude, line, end]
        seen.add(value)
    return '\n'.join([
        '// Copyright (C) 2026 @nightcodex7',
        '// SPDX-License-Identifier: GPL-3.0-or-later',
        '// GENERATED CODE - regenerate with scripts/generate_ui_copy.py.',
        "part of 'ui_copy.dart';", '',
        '_UiCopyCatalog _buildUiCopyCatalog(AppLocalizations l10n) => _UiCopyCatalog(',
        '  {', *exact, '  },', '  [', *patterns, '  ],', ');', '',
    ])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = generate()
    if args.check:
        # dart format may wrap calls and add trailing commas. Compare Dart
        # tokens rather than making formatter whitespace part of the catalog.
        def normalize(source):
            tokens = re.findall(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|\w+|[^\s]', source)
            return [token for token in tokens if token != ',' and not token.startswith('//')]
        if not OUTPUT.exists() or normalize(OUTPUT.read_text()) != normalize(expected):
            raise SystemExit('Run python3 scripts/generate_ui_copy.py')
    else:
        OUTPUT.write_text(expected)


if __name__ == '__main__':
    main()
