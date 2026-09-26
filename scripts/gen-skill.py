#!/usr/bin/env python3
"""plugin/skills/lidon/SKILL.md → Sources/LidOnCore/LidOnSkill.swift (앱과 CLI가 스킬을 설치할 때 쓰는 사본)"""
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
md = (root / "plugin/skills/lidon/SKILL.md").read_text(encoding="utf-8")
assert '"""#' not in md
swift = ('// 자동 생성 파일 — plugin/skills/lidon/SKILL.md를 고친 뒤 scripts/gen-skill.py를 실행하세요.\n\n'
         'public enum LidOnSkill {\n    public static let markdown = #"""\n' + md + '"""#\n}\n')
(root / "Sources/LidOnCore/LidOnSkill.swift").write_text(swift, encoding="utf-8")
print("Sources/LidOnCore/LidOnSkill.swift")
