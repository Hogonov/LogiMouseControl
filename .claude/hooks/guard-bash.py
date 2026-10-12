#!/usr/bin/env python3
# guard-bash.py: блокирует Bash-команды, которые запрещает AGENTS.md.
# Событие: PreToolUse, matcher Bash (.claude/settings.json).
# Блокирует запуск самого приложения (кроме --render-artwork-preview),
# osascript, cliclick и scripts/setup-local-signing.sh. Exit 2 отменяет вызов,
# строка из stderr уходит Claude как причина.
# Проверка эвристическая: разбирает команду на подкоманды, учитывает
# обёртки (env, nohup, timeout...), "bash -c", "eval" и $(...). Сам ничего не
# запускает и не пишет. Тест: .claude/hooks/test-hooks.sh
import json
import os
import re
import shlex
import sys

SEPARATORS = {";", ";;", "&", "&&", "|", "||", "|&", "(", ")", "{", "}", "!", "\n"}
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "time"}
WRAPPERS = {"env", "exec", "nohup", "sudo", "command", "caffeinate", "timeout", "gtimeout", "nice", "arch", "xcrun"}
SHELLS = {"sh", "bash", "zsh", "dash"}
APP_ALLOWED_FLAG = "--render-artwork-preview"
FALLBACK_WORDS = ("osascript", "cliclick", "setup-local-signing.sh", "Contents/MacOS/LogiMouseControl")


def tokenize(command):
    # $(...) и обратные кавычки становятся отдельными подкомандами.
    text = command.replace("$(", " ( ").replace("`", " ; ").replace("\n", " ; ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|(){}!")
    lexer.whitespace_split = True
    return list(lexer)


def split_commands(tokens):
    current = []
    for token in tokens:
        if token in SEPARATORS:
            if current:
                yield current
            current = []
        elif not current and token in KEYWORDS:
            continue
        else:
            current.append(token)
    if current:
        yield current


def strip_wrappers(words):
    while words:
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            words = words[1:]
        elif os.path.basename(words[0]) in WRAPPERS:
            words = words[1:]
            while words and (words[0].startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or re.match(r"^\d+[smhd]?$", words[0])):
                words = words[1:]
        else:
            return words
    return words


def is_app_binary(word):
    return word.endswith("/Contents/MacOS/LogiMouseControl") or os.path.basename(word) == "LogiMouseControl"


def reason_for(words, depth):
    words = strip_wrappers(words)
    if not words:
        return None
    program, args = words[0], words[1:]
    name = os.path.basename(program)

    if name == "osascript":
        return "osascript может нажимать клавиши и управлять приложениями"
    if name == "cliclick":
        return "cliclick имитирует нажатия мыши"
    if name == "setup-local-signing.sh":
        return "setup-local-signing.sh меняет связку ключей; его запускает только пользователь"
    if is_app_binary(program) and APP_ALLOWED_FLAG not in args:
        return "запуск LogiMouseControl управляет мышью; разрешён только флаг " + APP_ALLOWED_FLAG
    if name == "open" and any("Logi Mouse Control" in a or "LogiMouseControl" in a for a in args):
        return "open запускает приложение Logi Mouse Control"
    if name == "swift" and args[:1] == ["run"] and "LogiMouseControl" in args and APP_ALLOWED_FLAG not in args:
        return "swift run LogiMouseControl запускает приложение"

    if depth < 3:
        nested = None
        if name in SHELLS and "-c" in args:
            index = args.index("-c")
            nested = args[index + 1] if index + 1 < len(args) else None
        elif name == "eval":
            nested = " ".join(args)
        if nested:
            return check(nested, depth + 1)
    return None


def check(command, depth=0):
    try:
        tokens = tokenize(command)
    except ValueError:
        # Не удалось разобрать (например, незакрытая кавычка): решаем по словам.
        for word in FALLBACK_WORDS:
            if word in command:
                return "команда не разобрана и содержит " + word
        return None
    for words in split_commands(tokens):
        reason = reason_for(words, depth)
        if reason:
            return reason
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (event.get("tool_input") or {}).get("command") or ""
    reason = check(command)
    if reason:
        print(
            "Blocked: " + reason + ". AGENTS.md запрещает имитировать нажатия, прокрутку "
            "и запускать назначенные действия; это проверяет пользователь сам.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
