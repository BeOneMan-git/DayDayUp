#!/usr/bin/env python3
"""Build a Simplified Chinese HTML report from a DayDayUp simulator walk.

Reads manifest.jsonl (or DDU_SHOT lines in the xcodebuild log) and PNG
screenshots. Writes report.html next to the screenshots.

Exits 1 when a screen was not actually checked, when a record has an issue,
or when there are no records. Article titles from the pack manifest are
removed from the log and the report before anything is uploaded.
"""

from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path

BODY_NAME_PARTS = ("reader", "shadow", "baseline-quiz", "baseline-listening")


def load_choice(path: Path) -> dict[str, str]:
    choice: dict[str, str] = {}
    if not path.is_file():
        return choice
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        choice[key.strip()] = value.strip()
    return choice


def load_records(out: Path, log: Path | None) -> list[dict]:
    records: list[dict] = []
    manifest = out / "manifest.jsonl"
    if manifest.is_file():
        for line in manifest.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    if records:
        return records
    if log and log.is_file():
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            marker = "DDU_SHOT "
            index = line.find(marker)
            if index < 0:
                continue
            payload = line[index + len(marker) :].strip()
            try:
                records.append(json.loads(payload))
            except json.JSONDecodeError:
                continue
    return records


def manifest_titles(path: Path | None) -> list[str]:
    if path is None or not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    articles = data.get("articles") or []
    titles: list[str] = []
    pack_title = data.get("title")
    if isinstance(pack_title, str) and len(pack_title.strip()) >= 4:
        titles.append(pack_title.strip())
    for article in articles:
        if not isinstance(article, dict):
            continue
        title = article.get("title")
        if isinstance(title, str) and len(title.strip()) >= 4:
            titles.append(title.strip())
    titles.sort(key=len, reverse=True)
    return titles


def redact_text(text: str, titles: list[str]) -> str:
    for title in titles:
        text = text.replace(title, "[文章标题已省略]")
    return text


def redact_file(path: Path, titles: list[str]) -> None:
    if not titles or not path.is_file():
        return
    original = path.read_text(encoding="utf-8", errors="replace")
    updated = redact_text(original, titles)
    if updated != original:
        path.write_text(updated, encoding="utf-8")


def redact_outputs(out: Path, log: Path | None, titles: list[str]) -> None:
    if not titles:
        return
    if log is not None:
        redact_file(log, titles)
    for path in out.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".html", ".json", ".jsonl", ".txt", ".log"}:
            redact_file(path, titles)


def drop_body_pngs(out: Path) -> None:
    for path in out.rglob("*.png"):
        name = path.name.lower()
        if any(part in name for part in BODY_NAME_PARTS):
            path.unlink()


def hides_body(record: dict) -> bool:
    if record.get("body") is True:
        return True
    name = str(record.get("id") or "").lower()
    return any(part in name for part in BODY_NAME_PARTS)


def find_png(out: Path, record: dict) -> Path | None:
    if hides_body(record):
        return None
    file_name = record.get("file") or f"{record.get('id', '')}.png"
    direct = out / file_name
    if direct.is_file():
        return direct
    stem = Path(str(file_name)).stem
    matches = sorted(out.rglob(f"{stem}*.png"))
    return matches[0] if matches else None


def esc(text: object) -> str:
    return html.escape("" if text is None else str(text), quote=True)


def environment_section(choice: dict[str, str]) -> str:
    name = choice.get("name") or "（这次日志里没有设备名）"
    os_version = choice.get("os") or "（这次日志里没有系统版本）"
    runtime = choice.get("runtime_name") or "（没有运行时名字）"
    udid = choice.get("udid") or "（没有 UDID）"
    destination = choice.get("destination") or "（没有 destination）"
    installed = choice.get("installed_ios_runtimes") or "（没有列出）"
    exact = "是" if choice.get("exact_12_9_3rd") == "true" else "不是"
    created = "这次新建了一台。" if choice.get("created") == "true" else "用的是镜像里已经有的设备。"
    return f"""
    <h2>测试环境</h2>
    <p>这一节只写这次 GitHub Actions 日志里实际出现的模拟器，不写没有装上的系统。</p>
    <ul>
      <li>运行器：<code>macos-26</code></li>
      <li>设备：{esc(name)}</li>
      <li>simctl 运行时：{esc(runtime)}（版本 {esc(os_version)}）</li>
      <li>是不是 iPad Pro 12.9 英寸（第三代）：{exact}。{created}</li>
      <li>UDID：<code>{esc(udid)}</code></li>
      <li>xcodebuild destination：<code>{esc(destination)}</code></li>
      <li>这台 Mac 上已安装的 iOS 运行时：{esc(installed)}</li>
    </ul>
    <p>模拟器列表里的系统名叫 iOS，没有单独名叫 iPadOS 的运行时。iPad 模拟器用的就是这个 iOS 运行时。DayDayUp 的部署目标仍是 iPadOS 26.0。启动的是 DayDayUp 本身，不是逻辑测试那个小宿主。</p>
    """


def process_section() -> str:
    return """
    <h2>测试过程</h2>
    <ol>
      <li>只有手动运行 UI Walk 才会点界面。内容包从仓库 secret 下载；仓库里不保存地址，也不提交内容包。</li>
      <li>内容包只放进模拟器 App 的文稿文件夹。安装目录不会预先解包。走查要点开导入提示里的预览，确认后再看文章是否出现在书架。</li>
      <li>文章标题在运行时从内容包清单读取。报告和日志在上传前去掉这些标题。</li>
      <li>听读正文、中文翻译、理解题、跟读句子和基线短听读会核对是否打开，但不保存截图，也不上传 xcresult 附件。</li>
      <li>没有点会开始录音的按钮。必开的一屏如果没打开，这一次走查记为失败。</li>
    </ol>
    """


def uncovered_section() -> str:
    return """
    <h2>没覆盖到的部分</h2>
    <p>下面这些这次没有做，也不能用这次模拟器结果代替。</p>
    <ul>
      <li>真机。你的 iPad Pro 12.9 英寸（第三代）和这台模拟器不是同一台设备。分屏、横竖屏手感、点词，都要在 iPad 上看。</li>
      <li>签名。未签名 IPA、AltServer、免费 Apple ID 每周重装，这次都没有做。</li>
      <li>麦克风。模拟器没有你的麦克风。跟读录音、口语录音、基线“看题并开始”都没有按下去。</li>
      <li>Apple Pencil。模拟器里没有 Pencil 的压感和手写。</li>
      <li>文章正文和中文译文的截图。这些屏如果打开了，只在记录里写核对结果，图不进产物。</li>
    </ul>
    """


def screen_section(records: list[dict], out: Path) -> str:
    if not records:
        return """
        <h2>逐屏结果</h2>
        <p>这次没有逐屏记录。走查不能算通过。</p>
        """
    blocks = ["<h2>逐屏结果</h2>", "<p>下面每一节对应一次实际核对。有问题的会写原因；没打开的不算通过。</p>"]
    for record in records:
        title = record.get("title") or record.get("id")
        area = record.get("area") or ""
        did = record.get("did") or ""
        saw = record.get("saw") or ""
        issue = str(record.get("issue") or "").strip()
        checked = record.get("checked") is True
        if hides_body(record):
            figure = "<p>这一屏已核对，但不保存截图，避免把文章正文或中文译文放进公开产物。</p>"
        else:
            image = find_png(out, record)
            if image is not None:
                relative = image.relative_to(out).as_posix() if image.is_relative_to(out) else image.name
                figure = f'<img src="{esc(relative)}" alt="{esc(title)}">'
            else:
                figure = "<p>这张图没有写进产物目录。</p>"
        if issue:
            issue_html = f"<p><strong>问题：</strong>{esc(issue)}</p>"
        elif checked:
            issue_html = "<p><strong>结果：</strong>这一屏已经核对过。</p>"
        else:
            issue_html = "<p><strong>问题：</strong>这一屏没有实际核对。</p>"
        blocks.append(
            f"""
            <section>
              <h3>{esc(area)} · {esc(title)}</h3>
              {figure}
              <p><strong>做了什么：</strong>{esc(did)}</p>
              <p><strong>看到什么：</strong>{esc(saw) if saw else "（界面文字不写入这篇报告）"}</p>
              {issue_html}
            </section>
            """
        )
    return "\n".join(blocks)


def failure_reasons(records: list[dict]) -> list[str]:
    if not records:
        return ["没有逐屏记录，不能把这次走查看成通过。"]
    reasons: list[str] = []
    for record in records:
        ident = str(record.get("id") or record.get("title") or "未命名")
        if record.get("checked") is not True:
            reasons.append(f"{ident} 没有实际核对。")
        issue = str(record.get("issue") or "").strip()
        if issue:
            reasons.append(f"{ident}：{issue}")
    return reasons


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--choice", type=Path, required=True)
    parser.add_argument("--log", type=Path, default=None)
    parser.add_argument("--redact-manifest", type=Path, default=None)
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    titles = manifest_titles(args.redact_manifest)
    drop_body_pngs(out)
    redact_outputs(out, args.log, titles)
    choice = load_choice(args.choice)
    records = load_records(out, args.log)
    body = "\n".join(
        [
            environment_section(choice),
            process_section(),
            screen_section(records, out),
            uncovered_section(),
        ]
    )
    document = f"""<!DOCTYPE html>
<html lang="zh-Hans">
<head>
  <meta charset="utf-8">
  <title>DayDayUp 模拟器走查</title>
  <style>
    body {{ font-family: "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", sans-serif; line-height: 1.55; max-width: 980px; margin: 32px auto; padding: 0 16px; color: #1c1c1c; }}
    img {{ max-width: 100%; height: auto; border: 1px solid #ccc; margin: 8px 0 16px; }}
    code {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
    h1 {{ font-size: 1.6rem; }}
    h2 {{ margin-top: 2rem; border-top: 1px solid #ddd; padding-top: 1rem; }}
    section {{ margin: 1.5rem 0 2rem; }}
  </style>
</head>
<body>
  <h1>DayDayUp 模拟器走查</h1>
  <p>给 Song Johnson。图是这次 iPad 模拟器里打开 DayDayUp 后截的。带文章正文或中文译文的屏幕只核对、不截图。</p>
  {body}
</body>
</html>
"""
    report = out / "report.html"
    report.write_text(redact_text(document, titles), encoding="utf-8")
    reasons = failure_reasons(records)
    if reasons:
        print("ui-walk 未通过：", file=sys.stderr)
        for reason in reasons:
            print(reason, file=sys.stderr)
        sys.exit(1)
    print(f"wrote {report} screens={len(records)}")


if __name__ == "__main__":
    main()
