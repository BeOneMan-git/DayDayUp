# DayDayUp 测试

测试在 GitHub 的 macOS 电脑上跑。Windows 电脑和 iPad 都不用装 Xcode。云端的 Linux 机器也不能开 iPad 模拟器。

装到 iPad 上仍按 [INSTALL.md](INSTALL.md)。这里不产生安装包，也不给 App 签名。

## 跑什么、在哪跑

三件事情分开：

| 工作流 | 文件 | 什么时候跑 | 做什么 |
|---|---|---|---|
| Build IPA | `.github/workflows/build.yml` | 推送到 main 或 dev，或手动。**不在 pull request 上跑。** | dev 只编译。main 打出未签名的 DayDayUp.ipa 并发布。同一台 Mac 上还会用 `swift test` 跑逻辑测试。 |
| Test | `.github/workflows/test.yml` | 推送到 main 或 dev、打开或更新 pull request，或手动 | 用钉死的 Xcode 和 XcodeGen 生成工程，再跑下面三项。不打 ipa，不发布，也不点 App 界面。 |
| UI Walk | `.github/workflows/ui-walk.yml` | **只有手动。** 不随推送或 pull request 跑，也没有定时。 | 有内容包时，把 DayDayUp 装进 iPad 模拟器并逐屏核对。 |

Test 失败不会拦住 main 上的安装包：它和 Build IPA 是两个工作流。dev 上原来的“只编译”还在 Build IPA 里，没有改。

Build IPA 自己的 `swift test` 用了 `if: always()`，所以编译失败以后仍会跑逻辑测试。后面的打包、上传和发布只写了 `if: github.ref == 'refs/heads/main'`，没有 `always()`。这些步骤要等前面的步骤成功。所以 **Build IPA 里的逻辑测试如果失败，未签名 IPA 不会打出来。** 这和 “Test 工作流失败不挡住 IPA” 是两件事。

Test 里的三项：

1. **逻辑测试（Mac 本机）**。把 `DayDayUp/Logic` 和两个数据模型拷进 `LogicTests`，运行 `swift test`。这一步在选择模拟器之前，不看模拟器有没有选上。和 Build IPA 里的是同一套用例。
2. **按 iPad 模拟器编译 App**。Debug。部署目标仍是 iPadOS 26。选中的模拟器如果低于 26，就只按模拟器 SDK 编译，不往那台低版本模拟器里装。模拟器没选上时，这一步和下面一步不跑，第 1 步的结果仍然算数。
3. **同一套用例放进 iPad 模拟器再跑**。用例编进测试包，由一个很小的宿主 App 启动。这个宿主叫 `LogicTestHost`，部署目标是 **iOS 17.0**，只给测试用，不会装到你的 iPad。DayDayUp 自己的部署目标仍是 iPadOS 26。宿主把部署目标放低，是为了在没有 iOS 26 运行时的时候仍能跑这些用例。拷进测试包的逻辑如果写了 `#available`，在 iOS 17 的宿主里和在 iPadOS 26 的 App 里可能走不同的分支。

Xcode 钉在 `/Applications/Xcode_26.6.app`。XcodeGen 钉在 **2.46.0**，从 GitHub 的发布包安装，不用未钉版本的 `brew install xcodegen`。Test 和 UI Walk 共用 `.github/scripts/pin-tools.sh`。

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

逻辑测试不打开 DayDayUp 的界面。界面走查看下一节。

## 界面走查

UI Walk 用 scheme `UIWalk` 把 DayDayUp 装进上面那种 iPad 模拟器并启动。`UIWalk` 不在 `DayDayUp` scheme 里，所以不参与未签名 IPA。

仓库里没有 `.ecopack`，工作流文件里也没有下载地址，也不会向隧道发送 OIDC 令牌。要跑走查，在仓库的 Actions secrets 里加 **`DDU_PACK_URL`**，值是这次允许下载的内容包地址。地址只存在 secret 里。

没有这个 secret、下载失败，或文件里没有带文章的 `manifest.json` 时，日志写一行「跳过 ui-walk」，任务算通过，不会打开 App，也不会把 Test 工作流打红。没有定时任务：内容包不在仓库里，定时跑也拿不到包。

内容包只复制到模拟器 App 的文稿文件夹（`Documents/inbox.ecopack`）。不会预先解进 `Application Support/Packs`。走查要自己点「查看并导入」，等预览出现，点「导入所选」，看到「完成」，再在书架上看到清单里的文章。工具栏上一直都在的「导入内容包」按钮不算预览。文章标题在运行时从清单读取，不写进测试源码；上传前，日志和报告里的这些标题会被抹掉。

听读正文、播放、中文翻译、理解题、跟读句子、基线短听读的说明和题目会核对有没有打开，但**不上传这些截图，也不导出 xcresult 里的附件**。产物保留 3 天（`retention-days: 3`）。已经存在的旧产物不会因为这次改动被删掉。

必开的一屏如果没打开，测试里会 `XCTFail`（`continueAfterFailure = true`，后面的屏还会继续点），报告脚本见到问题或「没实际核对」的记录也会以退出码 1 结束。竖屏和横屏分成两个任务一起跑。点按分成 `test01` 到 `test07`，不再是一个从头睡到尾的长方法。

产物名是 **ui-walk-portrait** 和 **ui-walk-landscape**。下载后打开 `report.html`。

以前的几次运行还在：

- 2026-09-28 的空界面走查（[36451724213](https://github.com/BeOneMan-git/DayDayUp/actions/runs/36451724213)）用的是 **iPad Pro (12.9-inch) (3rd generation)**、**iOS 26.5**（Xcode 26.6 / 17F113，模拟器 SDK `iphonesimulator26.5`）。截图是竖屏 2048×2732。当时没有内容包，听读正文和中文翻译没有打开，设置后半段到了 45 分钟上限。产物名是 **ui-walk**。
- 带内容包的那一次（[36537302834](https://github.com/BeOneMan-git/DayDayUp/actions/runs/36537302834)）大约跑了 1 小时 43 分。任务是绿的，但导入预览和「阅读字号与标注」没有打开（竖屏导入预览、竖屏和横屏的字号页）。那一次把正文截图放进了产物。现在这些失败会把走查打红，正文截图也不再上传。

## 怎么开一次

Test：

1. 打开 GitHub 仓库的 Actions。
2. 左边选 **Test**。
3. 点 **Run workflow**，选 `main` 或 `dev`，再确认运行。

往 `main` 或 `dev` 推代码，或者开一个 pull request，也会自动跑 Test。不会自动跑 UI Walk，也不会在 pull request 上跑 Build IPA。

UI Walk：

1. 先在仓库 secrets 里放好 `DDU_PACK_URL`。没有的话，手动跑也会跳过并保持绿色。
2. Actions 里选 **UI Walk**，点 **Run workflow**。

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

所以这次实际用的是：**iPad Pro (12.9-inch) (3rd generation)**，系统 **iOS 26.5**。DayDayUp 按这台模拟器编译通过，部署目标仍是 iPadOS 26.0。38 个逻辑用例，Mac 上和这台模拟器里各一遍，都是 0 失败。那一次模拟器里启动的是测试宿主，不是把 DayDayUp 打开来点界面。后来的 UI Walk（上面的 [36537302834](https://github.com/BeOneMan-git/DayDayUp/actions/runs/36537302834)）才会打开 DayDayUp 本身。

以后 GitHub 换了镜像，以那次运行的 `simctl` 和 `showsdks` 日志为准。规则不变：有 iOS 26 就用其中最新的一套，并尽量用这台第三代。

## 这不能代替你的 iPad

下面这些还是要按 [INSTALL.md](INSTALL.md) 在 iPad Pro 12.9 英寸（第三代）、iPadOS 26 上看：

- AltServer 签名、每周重装、签名过期后打不开
- 麦克风和跟读录音
- Apple Pencil
- 真机上的屏幕、分屏、横竖屏、点词

逻辑测试的宿主是 iOS 17.0，App 是 iPadOS 26，两边的系统版本判断可以不一样。手动跑起来的界面走查会打开 DayDayUp，但它仍然不是你那台 iPad。
