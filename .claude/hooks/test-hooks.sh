#!/bin/bash
# Проверяет хуки из .claude/hooks без Claude: подаёт им на stdin такой же JSON,
# какой присылает Claude Code, и сверяет код выхода и вывод. Ничего не
# запускает из проверяемых команд; пишет только во временную папку.
# Запуск: .claude/hooks/test-hooks.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
hooks=$PWD/.claude/hooks
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

app='"dist/Logi Mouse Control.app/Contents/MacOS/LogiMouseControl"'
expect_bash() {
  local want=$1 command=$2 got=0
  jq -nc --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}' | "$hooks/guard-bash.py" 2> "$tmp/stderr" || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL guard-bash: exit $got, ожидался $want: $command"; failures=$((failures + 1))
  elif [ "$want" = 2 ] && ! grep -q '^Blocked: ' "$tmp/stderr"; then
    echo "FAIL guard-bash: нет строки Blocked: для $command"; failures=$((failures + 1))
  fi
}

# Блокируются.
expect_bash 2 "osascript -e 'tell application \"System Events\" to key code 49'"
expect_bash 2 'cliclick c:100,100'
expect_bash 2 './scripts/setup-local-signing.sh'
expect_bash 2 "$app"
expect_bash 2 "$app --diagnose"
expect_bash 2 '.build/debug/LogiMouseControl'
expect_bash 2 'open "dist/Logi Mouse Control.app"'
expect_bash 2 'open -a "Logi Mouse Control"'
expect_bash 2 'swift run LogiMouseControl'
expect_bash 2 './scripts/build.sh && open "dist/Logi Mouse Control.app"'
expect_bash 2 'bash -c "osascript -e beep"'
expect_bash 2 "echo \$(osascript -e 'beep')"
expect_bash 2 "nohup env FOO=1 $app &"
expect_bash 2 'timeout 5 cliclick c:1,1'
expect_bash 2 'eval "cliclick c:1,1"'
expect_bash 2 'if true; then osascript -e beep; fi'
expect_bash 2 "$(printf 'ls\nosascript -e beep')"

# Разрешены.
expect_bash 0 './scripts/test.sh'
expect_bash 0 './scripts/build.sh debug'
expect_bash 0 'swift build --product LogiMouseControl'
expect_bash 0 'swift run --disable-sandbox --scratch-path .build MouseCoreChecks'
expect_bash 0 "$app --render-artwork-preview /tmp/logimouse-artwork-preview"
expect_bash 0 'grep -rn osascript Sources'
expect_bash 0 "ls -l $app"
expect_bash 0 'codesign --verify --strict "dist/Logi Mouse Control.app"'
expect_bash 0 'cat scripts/setup-local-signing.sh'
expect_bash 0 'git log --oneline -5'

# check-test-registration.py: молчит на исправном файле, сообщает о
# незарегистрированной проверке и неверном счётчике, не трогает другие файлы.
project=$tmp/project
mkdir -p "$project/Tests/MouseCoreTests"
target=$project/Tests/MouseCoreTests/MouseCoreTests.swift
cp Tests/MouseCoreTests/MouseCoreTests.swift "$target"
run_registration() {
  jq -nc --arg p "$1" '{tool_name: "Edit", tool_input: {file_path: $p}}' | CLAUDE_PROJECT_DIR=$project "$hooks/check-test-registration.py"
}
expect_registration() {
  local label=$1 path=$2 pattern=$3 out
  out=$(run_registration "$path")
  if [ -z "$pattern" ] && [ -n "$out" ]; then
    echo "FAIL check-test-registration ($label): ожидалась тишина, получено: $out"; failures=$((failures + 1))
  elif [ -n "$pattern" ] && ! jq -e --arg p "$pattern" '.decision == "block" and (.reason | contains($p))' <<<"$out" > /dev/null 2>&1; then
    echo "FAIL check-test-registration ($label): нет \"$pattern\" в: $out"; failures=$((failures + 1))
  fi
}
expect_registration "исходный файл" "$target" ""
python3 - "$target" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("final class MouseCoreTests {", "final class MouseCoreTests {\n    func testNewCheck() {}", 1)
open(path, "w", encoding="utf-8").write(text)
PY
expect_registration "новый тест без вызова" "$target" "testNewCheck"
python3 - "$target" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace('        print("22 checks passed")', '        suite.testNewCheck(); print("PASS testNewCheck")\n        print("22 checks passed")', 1)
open(path, "w", encoding="utf-8").write(text)
PY
expect_registration "вызов без нового счётчика" "$target" "22 checks passed"
sed -i '' 's/print("22 checks passed")/print("23 checks passed")/' "$target"
expect_registration "всё зарегистрировано" "$target" ""
sed -i '' 's/print("23 checks passed")/print("99 checks passed")/' "$target"
expect_registration "другой файл" "$project/Tests/SpotlightShortcutChecks/main.swift" ""
# В worktree CLAUDE_PROJECT_DIR указывает на основную копию, а правка идёт в другую папку.
worktree=$tmp/project/.claude/worktrees/x
mkdir -p "$worktree/Tests/MouseCoreTests"
cp "$target" "$worktree/Tests/MouseCoreTests/MouseCoreTests.swift"
expect_registration "правка в worktree" "$worktree/Tests/MouseCoreTests/MouseCoreTests.swift" "99 checks passed"

if [ "$failures" -gt 0 ]; then
  echo "$failures проверок не прошли"; exit 1
fi
echo "PASS: хуки работают как ожидается"
