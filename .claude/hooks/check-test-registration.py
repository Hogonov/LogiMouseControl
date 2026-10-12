#!/usr/bin/env python3
# check-test-registration.py: после правки проверок сверяет, что каждый
# func test… из MouseCoreTests.swift вызывается в Checks.main() и что число
# в print("N checks passed") совпадает с числом вызовов.
# Событие: PostToolUse, matcher Edit|Write, if Edit(/Tests/**) (.claude/settings.json).
# Ничего не блокирует и не меняет: при расхождении возвращает JSON с
# decision "block", и Claude видит причину рядом с результатом правки.
# Тест: .claude/hooks/test-hooks.sh
import json
import os
import re
import sys

TARGET = os.path.join("Tests", "MouseCoreTests", "MouseCoreTests.swift")


def problems(source):
    marker = source.find("@main")
    if marker < 0:
        return ["не найден @main enum Checks"]
    body, runner = source[:marker], source[marker:]
    declared = re.findall(r"\bfunc\s+(test\w+)\s*\(", body)
    called = re.findall(r"\bsuite\.(test\w+)\s*\(", runner)
    labels = re.findall(r'print\("PASS (test\w+)"\)', runner)
    found = []

    missing = [name for name in declared if name not in called]
    if missing:
        found.append("не вызываются в Checks.main(): " + ", ".join(missing))
    unknown = [name for name in called if name not in declared]
    if unknown:
        found.append("Checks.main() вызывает несуществующие методы: " + ", ".join(unknown))
    duplicates = sorted({name for name in called if called.count(name) > 1})
    if duplicates:
        found.append("вызываются больше одного раза: " + ", ".join(duplicates))
    unlabeled = [name for name in called if name not in labels]
    if unlabeled:
        found.append('нет print("PASS …") для: ' + ", ".join(unlabeled))

    total = re.search(r'print\("(\d+) checks passed"\)', runner)
    if not total:
        found.append('не найден print("N checks passed")')
    elif int(total.group(1)) != len(called):
        found.append('print("%s checks passed") не совпадает с числом вызовов: %d' % (total.group(1), len(called)))
    return found


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    # Путь берётся из события, а не из CLAUDE_PROJECT_DIR: в worktree-сессии
    # CLAUDE_PROJECT_DIR указывает на основную копию, а правка идёт в worktree.
    target = (event.get("tool_input") or {}).get("file_path") or ""
    if not os.path.normpath(target).endswith(os.sep + TARGET) or not os.path.isfile(target):
        return 0
    with open(target, encoding="utf-8") as f:
        found = problems(f.read())
    if found:
        print(json.dumps({
            "decision": "block",
            "reason": "MouseCoreTests.swift: " + "; ".join(found)
            + ". Методы test… запускаются только из Checks.main(), см. .claude/rules/checks.md.",
        }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
