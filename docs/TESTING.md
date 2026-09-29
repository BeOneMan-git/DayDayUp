# DayDayUp 测试

测试在 GitHub 的 macOS 电脑上跑。Windows 电脑和 iPad 都不用装 Xcode。云端的 Linux 机器也不能开 iPad 模拟器。

装到 iPad 上仍按 [INSTALL.md](INSTALL.md)。这里不产生安装包，也不给 App 签名。

## 跑什么、在哪跑

两件事情分开：

| 工作流 | 文件 | 什么时候跑 | 做什么 |
|---|---|---|---|
| Build IPA | `.github/workflows/build.yml` | 推送到 main 或 dev，或手动 | dev 只编译。main 打出未签名的 DayDayUp.ipa 并发布。同一台 Mac 上还会用 `swift test` 跑逻辑测试。 |
| Test | `.github/workflows/test.yml` | 推送到 main 或 dev、打开或更新 pull request，或手动 | 用 XcodeGen 生成工程，再跑下面三项。不打 ipa，不发布。 |

Test 和 Build IPA 同时跑。Test 失败不会拦住 main 上的安装包。dev 上原来的“只编译”还在 Build IPA 里，没有改。

Test 里的三项：

1. **逻辑测试（Mac 本机）**。把 `DayDayUp/Logic` 和两个数据模型拷进 `LogicTests`，运行 `swift test`。和 Build IPA 里的是同一套用例。
2. **按 iPad 模拟器编译 App**。Debug。部署目标仍是 iPadOS 26。选中的模拟器如果低于 26，就只按模拟器 SDK 编译，不往那台低版本模拟器里装。
3. **同一套用例放进 iPad 模拟器再跑**。用例编进测试包，由一个很小的宿主 App 启动。这个宿主叫 `LogicTestHost`，只给测试用，不会装到你的 iPad。DayDayUp 自己的部署目标仍是 iPadOS 26，所以它不能在更低的模拟器系统里启动；宿主把部署目标放低，就是为了在没有 iOS 26 运行时的时候仍能跑这些用例。

用例都在 `LogicTests/Tests/DDULogicTests/`：

- `FSRSTests`：词汇排期，和 py-fsrs 对照
- `QueueTests`：今天复习哪些词
- `PackDiffTests`：内容包里句子的增删改
- `DataFileTests`：记录文件里的坏行、词库解码
- `PlanEngineTests`：今日计划怎么排
- `MetricsTests`：练习时间和统计
- `SentenceTextTests`：句子文本和哈希
- `AnswerCheckTests`：拼写和词形对错
- `CSVTests`：导入表格

另外有一次界面走查，和上面的逻辑测试分开跑，见下一节。逻辑测试仍不打开 DayDayUp 的界面。

## 界面走查

同一份 Test 工作流里还有一个任务叫 `ui-walk`。它用 scheme `UIWalk` 把 DayDayUp 装进上面选中的那台 iPad 模拟器并启动，然后点得开的页面都会截图。`UIWalk` 不在 `DayDayUp` scheme 里，所以不参与未签名 IPA。

仓库里仍然没有 `.ecopack`（公开仓库不放内容包）。`ui-walk` 用本仓库的 GitHub OIDC 令牌向一次走查专用的地址领取 `DayDayUp-2026-09-12-2.ecopack`，放进模拟器 App 的文稿文件夹，并按 `PackImporter.write` 的目录解到 `Application Support/Packs/2026-09-12-2/`。走查不会按开始录音。

截图和中文报告在同一次运行的产物 **ui-walk** 里。下载后打开 `report.html`，图片在同一个目录。

2026-09-28 的界面走查（[36451724213](https://github.com/BeOneMan-git/DayDayUp/actions/runs/36451724213)）用的仍是 **iPad Pro (12.9-inch) (3rd generation)**、**iOS 26.5**（Xcode 26.6 / 17F113，模拟器 SDK `iphonesimulator26.5`）。截图是竖屏 2048×2732。这一轮在设置后半段到了当时的 45 分钟上限，任务被停掉，已经截到的图仍在产物 **ui-walk** 里。仓库里没有内容包，听读正文和中文翻译没有打开。

## 怎么开一次

1. 打开 GitHub 仓库的 Actions。
2. 左边选 **Test**。
3. 点 **Run workflow**，选 `main` 或 `dev`，再确认运行。

往 `main` 或 `dev` 推代码，或者开一个 pull request，也会自动跑。手动运行要等这个文件已经在那个分支上。

看结果：点进那一次运行。**Show toolchain and simulators** 里是 `xcodebuild -version`、`xcodebuild -showsdks` 和 `xcrun simctl list` 的原文。**Choose iPad simulator** 里是选中的设备和系统。

## 模拟器怎么选

优先用 iOS 26 运行时（`simctl` 里 iPad 模拟器的系统就叫 iOS，没有单独的 “iPadOS” 运行时名字）上的 **iPad Pro 12.9 英寸（第三代）**。设备类型在、但还没建好时，工作流会建一台。

如果镜像里没有这台第三代，就在同一套 iOS 26 上选最接近的 iPad：先任何 12.9 英寸，再 13 英寸的 iPad Pro（12.9 英寸那条产品线后来换成了 13 英寸），然后才是别的 iPad。

如果镜像里没有 iOS 26 运行时，就用已经装好的最新 iPad 模拟器，并在日志里写明。不会把没装上的系统写成已经在用。

## 这次核对到的结果

2026-09-28 的 Test 运行（[36427386930](https://github.com/BeOneMan-git/DayDayUp/actions/runs/36427386930)）里，日志原文是：

- `xcodebuild -version`：Xcode 26.6（17F113）。
- `xcodebuild -showsdks`：当前这套 Xcode 的模拟器 SDK 是 **Simulator - iOS 26.5**（`iphonesimulator26.5`）。设备 SDK 是 iOS 26.5。这份列表里没有更低的 iOS SDK。
- `xcrun simctl list runtimes`：已安装 **iOS 26.2**、**iOS 26.4**（版本号 26.4.1）、**iOS 26.5**。没有单独名叫 iPadOS 的运行时，iPad 模拟器用的就是这些 iOS 运行时。没有另外下载运行时。

镜像里预先建好的 iPad（iOS 26.5）是：iPad Pro 13-inch (M5)、iPad Pro 11-inch (M5)、iPad mini (A17 Pro)、iPad Air 13-inch (M4)、iPad Air 11-inch (M4)、iPad (A16)。里面没有 12.9 英寸第三代。

设备类型里有 **iPad Pro (12.9-inch) (3rd generation)**，iOS 26.5 能用。工作流新建了一台，测试和 App 编译都用它。`xcodebuild` 的目标行是：`OS:26.5, name:iPad Pro (12.9-inch) (3rd generation)`。

所以这次实际用的是：**iPad Pro (12.9-inch) (3rd generation)**，系统 **iOS 26.5**。DayDayUp 按这台模拟器编译通过，部署目标仍是 iPadOS 26.0。38 个逻辑用例，Mac 上和这台模拟器里各一遍，都是 0 失败。模拟器里启动的是测试宿主，不是把 DayDayUp 打开来点界面。

以后 GitHub 换了镜像，以那次运行的 `simctl` 和 `showsdks` 日志为准。规则不变：有 iOS 26 就用其中最新的一套，并尽量用这台第三代。

## 这不能代替你的 iPad

下面这些 Test 碰不到，还是要按 [INSTALL.md](INSTALL.md) 在 iPad Pro 12.9 英寸（第三代）、iPadOS 26 上看：

- AltServer 签名、每周重装、签名过期后打不开
- 麦克风和跟读录音
- Apple Pencil
- 真机上的屏幕、分屏、横竖屏、点词

模拟器只说明：这些逻辑用例能通过，App 能按 iPad 模拟器编出来。
