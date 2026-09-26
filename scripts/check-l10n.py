#!/usr/bin/env python3
"""앱 코드의 UI 문자열이 모두 한국어로 번역됐는지 확인한다. (CI에서 실행)"""
import glob, re, sys

pat = re.compile(r'(?:\bL|Text|Toggle|Label|Button|Picker|TableColumn|LabeledContent|Footnote|TextField|'
                 r'ContentUnavailableView|SliderRow\(title:|\.help\(Text)\(\s*"((?:[^"\\]|\\.)*)"')
pat_title = re.compile(r'(?:title:|step\(\s*"[^"]*",|SettingLabel\(|\("[a-z.]+", [^,\n]+,)\s*"((?:[^"\\]|\\.)*)"')
keys = set()
for f in glob.glob('Sources/LidOnApp/*.swift'):
    src = open(f, encoding='utf-8').read()
    keys |= {m.group(1) for m in pat.finditer(src)} | {m.group(1) for m in pat_title.finditer(src)}

ko = set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', open('Resources/ko.lproj/Localizable.strings', encoding='utf-8').read(), re.M))
missing = sorted(keys - ko)
unused = sorted(ko - keys)
for k in missing: print(f'missing ko: "{k}"')
for k in unused: print(f'unused ko:  "{k}"')
sys.exit(1 if missing else 0)
