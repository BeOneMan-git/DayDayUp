#!/usr/bin/env python3
"""Pick an iPad Simulator from `xcrun simctl list` for the DayDayUp test workflow.

Preference, in order:
  1. An available iOS 26 runtime if the runner has one, otherwise the newest iOS runtime.
  2. On that runtime, iPad Pro 12.9-inch (3rd generation) — the physical iPad — creating
     it when the device type exists but no device has been created yet.
  3. Otherwise the closest iPad already created on that runtime: any 12.9-inch,
     then a 13-inch iPad Pro (the size that replaced 12.9-inch), then any other iPad.

Prints the choice and, on GitHub Actions, appends SIM_* variables to $GITHUB_ENV.
Does not invent a runtime: every field comes from simctl JSON.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Callable, Optional


def version_key(version: str) -> tuple:
    parts = []
    for piece in version.split("."):
        if piece.isdigit():
            parts.append(int(piece))
        else:
            break
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def is_exact_12_9_3rd(name: str) -> bool:
    lowered = name.lower()
    return "ipad" in lowered and "12.9" in lowered and "3rd" in lowered


def device_score(name: str) -> int:
    """Higher is closer to iPad Pro 12.9-inch (3rd generation). Non-iPads score -1."""
    if "iPad" not in name:
        return -1
    if is_exact_12_9_3rd(name):
        return 1000
    if "12.9" in name and "iPad Pro" in name:
        return 800
    if "12.9" in name:
        return 700
    if "13-inch" in name and "iPad Pro" in name:
        return 600
    if "13-inch" in name:
        return 400
    if "iPad Pro" in name:
        return 200
    return 100


def runtime_sort_key(runtime: dict) -> tuple:
    version = version_key(str(runtime.get("version") or "0"))
    # iPadOS 26 is the deployment target. Prefer it over both older and newer majors.
    prefer_26 = 1 if version[0] == 26 else 0
    return (prefer_26, version)


def find_12_9_3rd_type(device_types: list) -> Optional[dict]:
    for item in device_types:
        if is_exact_12_9_3rd(item.get("name", "")):
            return item
    return None


def type_supported(runtime: dict, device_type: dict) -> bool:
    # Missing key: simctl omitted the list, so try to create and fall back if it fails.
    # An empty list means this runtime declared no supported device types.
    if "supportedDeviceTypes" not in runtime or runtime["supportedDeviceTypes"] is None:
        return True
    supported = runtime["supportedDeviceTypes"]
    wanted_id = device_type.get("identifier")
    wanted_name = device_type.get("name")
    for item in supported:
        if item.get("identifier") == wanted_id or item.get("name") == wanted_name:
            return True
    return False


def devices_for(runtime: dict, devices_map: dict) -> list:
    identifier = runtime.get("identifier", "")
    name = runtime.get("name", "")
    if identifier in devices_map:
        return devices_map[identifier]
    if name in devices_map:
        return devices_map[name]
    for key, devices in devices_map.items():
        if identifier and identifier in key:
            return devices
    return []


def available_ipads(devices: list) -> list:
    chosen = []
    for device in devices:
        if device.get("isAvailable", True) is False:
            continue
        if device_score(device.get("name", "")) < 0:
            continue
        chosen.append(device)
    return chosen


def select(runtimes: list, devices_map: dict, device_types: list, create: Callable[[str, str, str], str]) -> dict:
    ios = []
    for runtime in runtimes:
        platform = runtime.get("platform") or ""
        identifier = runtime.get("identifier") or ""
        if platform != "iOS" and "iOS-" not in identifier and not str(runtime.get("name", "")).startswith("iOS"):
            continue
        if runtime.get("isAvailable", True) is False:
            continue
        ios.append(runtime)
    if not ios:
        raise SystemExit("simctl 没有可用的 iOS 运行时")

    ranked = sorted(ios, key=runtime_sort_key, reverse=True)
    device_type = find_12_9_3rd_type(device_types)
    installed = " ".join(
        str(runtime.get("version") or "?")
        for runtime in sorted(ios, key=lambda item: version_key(str(item.get("version") or "0")), reverse=True)
    )
    has_26 = any(version_key(str(runtime.get("version") or "0"))[0] == 26 for runtime in ios)
    twelve_nine = ", ".join(
        item.get("name", "") for item in device_types if "12.9" in item.get("name", "")
    ) or "(none)"

    last_error = "没有可用的 iPad 模拟器"
    for runtime in ranked:
        ipads = available_ipads(devices_for(runtime, devices_map))
        exact = [device for device in ipads if is_exact_12_9_3rd(device.get("name", ""))]
        if exact:
            device = sorted(exact, key=lambda item: item.get("name", ""))[0]
            return _choice(runtime, device, False, device_type, installed, has_26, ipads, twelve_nine)

        if device_type and type_supported(runtime, device_type):
            try:
                udid = create(device_type["name"], device_type["identifier"], runtime["identifier"]).strip()
            except Exception as error:  # creation is best-effort; an existing iPad still counts
                last_error = f"无法创建 {device_type.get('name')}: {error}"
                udid = ""
            if udid:
                device = {
                    "name": device_type["name"],
                    "udid": udid,
                    "isAvailable": True,
                }
                return _choice(runtime, device, True, device_type, installed, has_26, ipads, twelve_nine)

        if ipads:
            device = sorted(ipads, key=lambda item: (-device_score(item.get("name", "")), item.get("name", "")))[0]
            return _choice(runtime, device, False, device_type, installed, has_26, ipads, twelve_nine)

        version = runtime.get("version")
        last_error = f"iOS {version} 上没有可用的 iPad 模拟器"

    raise SystemExit(last_error)


def _choice(runtime, device, created, device_type, installed, has_26, ipads, twelve_nine) -> dict:
    version = str(runtime.get("version") or "")
    name = device["name"]
    udid = device["udid"]
    if device_type is None:
        type_state = "absent"
    elif type_supported(runtime, device_type):
        type_state = "supported"
    else:
        type_state = "unsupported"
    return {
        "name": name,
        "os": version,
        "udid": udid,
        "destination": f"platform=iOS Simulator,id={udid}",
        "runtime_name": runtime.get("name") or f"iOS {version}",
        "runtime_id": runtime.get("identifier") or "",
        "ipados_26_installed": "true" if has_26 else "false",
        "exact_12_9_3rd": "true" if is_exact_12_9_3rd(name) else "false",
        "created": "true" if created else "false",
        "device_type_12_9_3rd": type_state,
        "installed_ios_runtimes": installed,
        "candidate_ipads": ", ".join(
            f"{item.get('name')} ({runtime.get('version')})" for item in ipads
        ),
        "device_types_12_9": twelve_nine,
    }


def _simctl_json(*args: str) -> dict:
    raw = subprocess.check_output(["xcrun", "simctl", "list", *args, "-j"], text=True)
    return json.loads(raw)


def _create(name: str, device_type_id: str, runtime_id: str) -> str:
    return subprocess.check_output(
        ["xcrun", "simctl", "create", name, device_type_id, runtime_id],
        text=True,
    )


def _write_env(choice: dict) -> None:
    path = os.environ.get("GITHUB_ENV")
    lines = [
        f"SIM_NAME={choice['name']}",
        f"SIM_OS={choice['os']}",
        f"SIM_UDID={choice['udid']}",
        f"SIM_DESTINATION={choice['destination']}",
        f"SIM_RUNTIME_NAME={choice['runtime_name']}",
        f"SIM_RUNTIME_ID={choice['runtime_id']}",
        f"IPADOS_26_INSTALLED={choice['ipados_26_installed']}",
        f"EXACT_12_9_3RD={choice['exact_12_9_3rd']}",
        f"SIM_CREATED={choice['created']}",
        f"DEVICE_TYPE_12_9_3RD={choice['device_type_12_9_3rd']}",
        f"INSTALLED_IOS_RUNTIMES={choice['installed_ios_runtimes']}",
    ]
    text = "\n".join(lines) + "\n"
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text)
    print(text, end="")


def _write_summary(choice: dict) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    exact = "是" if choice["exact_12_9_3rd"] == "true" else "不是"
    has_26 = "有" if choice["ipados_26_installed"] == "true" else "没有"
    created = "这次新建了一台。" if choice["created"] == "true" else "用的是镜像里已经有的设备。"
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("## 选中的 iPad 模拟器\n\n")
        handle.write(f"- 设备：{choice['name']}\n")
        handle.write(f"- simctl 运行时：{choice['runtime_name']}（版本 {choice['os']}）\n")
        handle.write(f"- 运行时标识：`{choice['runtime_id']}`\n")
        handle.write(f"- 已安装的 iOS 运行时：{choice['installed_ios_runtimes']}\n")
        handle.write(f"- 有没有 iOS 26：{has_26}\n")
        handle.write(f"- 是不是 iPad Pro 12.9 英寸（第三代）：{exact}。{created}\n")
        handle.write(f"- 第三代设备类型：{choice['device_type_12_9_3rd']}\n")
        handle.write(f"- 设备类型里的 12.9 英寸：{choice['device_types_12_9']}\n")
        if choice["candidate_ipads"]:
            handle.write(f"- 同一运行时上已有的 iPad：{choice['candidate_ipads']}\n")
        handle.write("\n")


def _write_choice_file(choice: dict) -> None:
    with open("simulator-choice.txt", "w", encoding="utf-8") as handle:
        for key in (
            "name",
            "os",
            "udid",
            "destination",
            "runtime_name",
            "runtime_id",
            "ipados_26_installed",
            "exact_12_9_3rd",
            "created",
            "device_type_12_9_3rd",
            "installed_ios_runtimes",
            "candidate_ipads",
            "device_types_12_9",
        ):
            handle.write(f"{key}={choice[key]}\n")


def self_check() -> None:
    runtime_265 = {
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "name": "iOS 26.5",
        "version": "26.5",
        "platform": "iOS",
        "isAvailable": True,
        "supportedDeviceTypes": [
            {"name": "iPad Pro 13-inch (M5)", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5"},
        ],
    }
    runtime_262 = {
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
        "name": "iOS 26.2",
        "version": "26.2",
        "platform": "iOS",
        "isAvailable": True,
        "supportedDeviceTypes": [],
    }
    runtime_186 = {
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
        "name": "iOS 18.6",
        "version": "18.6",
        "platform": "iOS",
        "isAvailable": True,
        "supportedDeviceTypes": [
            {"name": "iPad Pro 13-inch (M4)", "identifier": "ipad-13-m4"},
        ],
    }
    ipad_13 = {"name": "iPad Pro 13-inch (M5)", "udid": "UDID-13", "isAvailable": True}
    ipad_11 = {"name": "iPad Pro 11-inch (M5)", "udid": "UDID-11", "isAvailable": True}
    iphone = {"name": "iPhone 17", "udid": "UDID-PHONE", "isAvailable": True}
    devices = {
        runtime_265["identifier"]: [iphone, ipad_11, ipad_13],
        runtime_262["identifier"]: [],
        runtime_186["identifier"]: [
            {"name": "iPad Pro 11-inch (M4)", "udid": "UDID-11-18", "isAvailable": True},
            {"name": "iPad Pro 13-inch (M4)", "udid": "UDID-13-18", "isAvailable": True},
        ],
    }

    def fail_create(name, device_type_id, runtime_id):
        raise AssertionError("should not create a device")

    choice = select([runtime_265, runtime_262, runtime_186], devices, [], fail_create)
    assert choice["name"] == "iPad Pro 13-inch (M5)", choice
    assert choice["os"] == "26.5", choice
    assert choice["exact_12_9_3rd"] == "false"
    assert choice["ipados_26_installed"] == "true"
    assert choice["udid"] == "UDID-13"

    created = {"called": False}

    def do_create(name, device_type_id, runtime_id):
        created["called"] = True
        assert "12.9" in name and "3rd" in name
        assert runtime_id == runtime_265["identifier"]
        return "UDID-NEW\n"

    dtype = {
        "name": "iPad Pro 12.9-inch (3rd generation)",
        "identifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-3rd",
    }
    runtime_with_type = dict(runtime_265)
    runtime_with_type["supportedDeviceTypes"] = [dtype, runtime_265["supportedDeviceTypes"][0]]
    choice = select([runtime_with_type], devices, [dtype], do_create)
    assert created["called"]
    assert choice["exact_12_9_3rd"] == "true"
    assert choice["udid"] == "UDID-NEW"
    assert choice["created"] == "true"

    # Newest iOS 26 runtime wins even if an older 26 runtime already has the exact iPad.
    runtime_265_no_type = dict(runtime_265)
    devices_with_old_exact = dict(devices)
    devices_with_old_exact[runtime_262["identifier"]] = [
        {"name": "iPad Pro 12.9-inch (3rd generation)", "udid": "UDID-OLD", "isAvailable": True}
    ]
    choice = select([runtime_265_no_type, runtime_262], devices_with_old_exact, [dtype], fail_create)
    assert choice["os"] == "26.5", choice
    assert choice["name"] == "iPad Pro 13-inch (M5)", choice

    choice = select([runtime_186], devices, [], fail_create)
    assert choice["os"] == "18.6"
    assert choice["name"] == "iPad Pro 13-inch (M4)"
    assert choice["ipados_26_installed"] == "false"

    try:
        select([runtime_265], {runtime_265["identifier"]: [iphone]}, [], fail_create)
    except SystemExit:
        pass
    else:
        raise AssertionError("iPhone-only runtime should fail")

    print("self-check ok")


def main() -> None:
    if "--self-check" in sys.argv:
        self_check()
        return
    runtimes = _simctl_json("runtimes").get("runtimes", [])
    devices_map = _simctl_json("devices", "available").get("devices", {})
    device_types = _simctl_json("devicetypes").get("devicetypes", [])
    choice = select(runtimes, devices_map, device_types, _create)
    _write_env(choice)
    _write_summary(choice)
    _write_choice_file(choice)


if __name__ == "__main__":
    main()
