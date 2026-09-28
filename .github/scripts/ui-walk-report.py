#!/usr/bin/env python3
"""Build a Simplified Chinese HTML report from a DayDayUp simulator walk.

Reads manifest.jsonl (or DDU_SHOT lines in the xcodebuild log) and PNG
screenshots. Writes report.html next to the screenshots.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


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


def find_png(out: Path, record: dict) -> Path | None:
    file_name = record.get("file") or f"{record.get('id', '')}.png"
    direct = out / file_name
    if direct.is_file():
        return direct
    stem = Path(file_name).stem
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
      <li>在 macos-26 上用 XcodeGen 生成工程，再用和逻辑测试相同的脚本选择 iPad 模拟器。</li>
      <li>用 scheme <code>UIWalk</code> 把 DayDayUp 装进这台模拟器并启动。这个 scheme 不参与未签名 IPA。</li>
      <li>界面测试在 Mac 上点模拟器里的 App：今日、基线、书架、跟读、雅思、词汇、进度、设置，以及从这些页面点得进去的子页。</li>
      <li>仓库里没有 <code>.ecopack</code> 内容包。没有文章的页面就停在空状态，不编造杂志内容。</li>
      <li>没有点会开始录音的按钮（“看题并开始”“直接开始说”“开始模拟”“开始准备”）。独立短文只打开编辑区，不保存。</li>
      <li>每一屏截一张全屏图。打不开的，截当时挡住的那一屏，并在下面写原因。</li>
    </ol>
    """


def uncovered_section(missing: list[str]) -> str:
    items = "".join(f"<li>{esc(item)}</li>" for item in missing)
    return f"""
    <h2>没覆盖到的部分</h2>
    <p>下面这些这次没有做，也不能用这次模拟器结果代替。</p>
    <ul>
      <li>真机。你的 iPad Pro 12.9 英寸（第三代）和这台模拟器不是同一台设备。分屏、横竖屏手感、点词，都要在 iPad 上看。</li>
      <li>签名。未签名 IPA、AltServer、免费 Apple ID 每周重装，这次都没有做。</li>
      <li>麦克风。模拟器没有你的麦克风。跟读录音、口语录音、基线“看题并开始”都没有按下去。</li>
      <li>Apple Pencil。模拟器里没有 Pencil 的压感和手写。</li>
      {items}
    </ul>
    """


def screen_section(records: list[dict], out: Path) -> str:
    if not records:
        return """
        <h2>逐屏结果</h2>
        <p>这次没有截到屏幕。请看同一次运行里的 ui-walk.log。</p>
        """
    blocks = ["<h2>逐屏结果</h2>", "<p>下面每一节都是这次实际打开（或尝试打开）的一屏。说明来自这次点击和屏幕上的文字。</p>"]
    for record in records:
        image = find_png(out, record)
        title = record.get("title") or record.get("id")
        area = record.get("area") or ""
        did = record.get("did") or ""
        saw = record.get("saw") or ""
        issue = record.get("issue") or ""
        figure = ""
        if image is not None:
            relative = image.relative_to(out).as_posix() if image.is_relative_to(out) else image.name
            figure = f'<img src="{esc(relative)}" alt="{esc(title)}">'
        else:
            figure = "<p>这张图没有写进产物目录。</p>"
        issue_html = f"<p><strong>问题：</strong>{esc(issue)}</p>" if issue else "<p><strong>问题：</strong>这一屏没有记到额外问题。</p>"
        blocks.append(
            f"""
            <section>
              <h3>{esc(area)} · {esc(title)}</h3>
              {figure}
              <p><strong>做了什么：</strong>{esc(did)}</p>
              <p><strong>看到什么：</strong>{esc(saw) if saw else "（没有读到界面文字）"}</p>
              {issue_html}
            </section>
            """
        )
    return "\n".join(blocks)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--choice", type=Path, required=True)
    parser.add_argument("--log", type=Path, default=None)
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    choice = load_choice(args.choice)
    records = load_records(out, args.log)
    missing = [
        "听读器（书架里的文章正文、点词、播放）。书架是空的，没有文章可点。",
        "朗读正文，以及工具栏里的“显示中文翻译 / 隐藏中文翻译”。这两项都在听读器里。",
        "跟读工作台（听后模仿、影子跟读、独立朗读、脱稿复述）。没有文章，只能看到空的选文页。",
        "基线的短听读理解题。没有带理解题的内容包。",
        "词汇自测的 24 个词。词库来自内容包，这次是空的。",
    ]
    body = "\n".join(
        [
            environment_section(choice),
            process_section(),
            screen_section(records, out),
            uncovered_section(missing),
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
  <p>给 Song Johnson。图是这次 iPad 模拟器里打开 DayDayUp 后截的。没有内容包的功能只写实际停住的那一屏。</p>
  {body}
</body>
</html>
"""
    (out / "report.html").write_text(document, encoding="utf-8")
    print(f"wrote {out / 'report.html'} screens={len(records)}")


if __name__ == "__main__":
    main()
