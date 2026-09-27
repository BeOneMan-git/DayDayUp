#!/usr/bin/env python3
"""Turns the UI tap test results into GitHub annotations, which the public API serves without a token.

gate    NavigationTapTests: a failed test is an error.
control LegacyRootTapDiagnosisTests: a passed test means 1.0.0's root tap gesture swallowed that tap, as
        expected; a failed one is only a warning (the control never blocks a build).
Also writes <out dir>/summary.txt. Reads <name>.xcresult (Xcode 16+ xcresulttool), else <name>.log.
Usage: ci/ui_summary.py <out dir>
"""
import json
import os
import re
import subprocess
import sys

GROUPS = [
    ("gate", "UI gate (new code)", "error",
     "Taps on the sidebar, a 书架 article, a 雅思 prompt, a 设置 row and the portrait tab bar must lead somewhere."),
    ("control", "UI control (1.0.0 root tap gesture)", "warning",
     "A pass here means the old root tap gesture made that tap lead nowhere."),
]


def esc_data(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def esc_prop(text):
    return esc_data(text).replace(":", "%3A").replace(",", "%2C")


def annotate(level, title, message):
    print(f"::{level} title={esc_prop(title)}::{esc_data(message[:3500])}")


def from_xcresult(path):
    if not os.path.isdir(path):
        return None
    try:
        raw = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path],
                             capture_output=True, text=True, timeout=180).stdout
        data = json.loads(raw)
    except Exception:
        return None
    cases = []

    def messages(node, found):
        if node.get("nodeType") == "Failure Message":
            found.append(node.get("name", ""))
        for child in node.get("children", []):
            messages(child, found)
        return found

    def walk(node):
        if node.get("nodeType") == "Test Case":
            cases.append((node.get("name", "?"), node.get("result", "?"), node.get("duration", ""),
                          messages(node, [])))
            return
        for child in node.get("children", []):
            walk(child)

    for node in data.get("testNodes", []):
        walk(node)
    return cases or None


CASE = re.compile(r"Test Case '-\[\S+ (\S+)\]' (passed|failed) \(([\d.]+) seconds\)")
ERROR = re.compile(r"error: -\[\S+ (\S+)\] : (.*)")


def from_log(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    errors = {}
    for test, message in ERROR.findall(text):
        errors.setdefault(test, []).append(message)
    return [(test, "Passed" if result == "passed" else "Failed", seconds + "s", errors.get(test, []))
            for test, result, seconds in CASE.findall(text)] or None


def main(out):
    lines = []
    for name, title, fail_level, meaning in GROUPS:
        cases = from_xcresult(os.path.join(out, name + ".xcresult")) or from_log(os.path.join(out, name + ".log"))
        if not cases:
            annotate(fail_level, title, "no test results; see the uploaded logs.")
            lines.append(f"{title}: no results")
            continue
        passed = [c for c in cases if c[1].lower() == "passed"]
        names = ", ".join(c[0] for c in passed) or "none"
        annotate("notice", title, f"{len(passed)}/{len(cases)} passed ({names}). {meaning}")
        lines.append(f"{title}: {len(passed)}/{len(cases)} passed")
        for test, result, duration, found in cases:
            text = f"{test}: {result} ({duration})"
            if found:
                text += " - " + " / ".join(found)
            lines.append("  " + text)
            if result.lower() != "passed":
                annotate(fail_level, title, text)
    with open(os.path.join(out, "summary.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
