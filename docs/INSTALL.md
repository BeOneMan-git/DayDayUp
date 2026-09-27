# DayDayUp 安装与使用说明（V0.2 说写起步）

这份说明带你把 DayDayUp 装到 iPad 上，并且每周更新。整个过程分四部分：装电脑端工具、装 App、导入内容包、每 7 天重装一次。前两部分只做一次。

- 电脑：Windows 电脑
- iPad：iPad Pro 12.9 英寸（第三代），iPadOS 26.x
- 账号：一个专门用来签名的 Apple ID（不用你的主账号）
- 一根能传数据的 USB 线

> 为什么要这样装：DayDayUp 不上架 App Store，只给你自己用。免费 Apple ID 可以给自己装的 App 签名，但签名只管 7 天，所以每周要重装一次。重装是覆盖安装，学习记录都在。

---

## 第一步：在 Windows 上装 iTunes、iCloud 和 AltServer（只做一次）

1. 如果电脑上装过“微软商店”版的 iTunes 或 iCloud，先卸载。AltServer 只认苹果官网的版本。
2. 从苹果官网下载并安装 iTunes（64 位）和 iCloud。下载链接在 AltStore 的官方说明里：
   <https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows>
3. 在同一个页面下载 AltServer（altinstaller.zip），解压后运行 Setup.exe。
4. 用管理员身份运行 AltServer。它只在任务栏右下角显示一个小图标（在 ^ 里面）。
5. 用数据线连好 iPad，iPad 保持解锁，点“信任此电脑”。
6. iTunes → 点 iPad 图标 → 勾“通过 Wi-Fi 与此 iPad 同步”，取消“连接时自动同步”，点“应用”。

## 第二步：iPad 上的设置（只做一次）

1. 第一次装好 App 以后，打开 **设置 → 通用 → VPN 与设备管理**，点你的签名 Apple ID，再点“信任”。这一步要联网。
2. 打开 **设置 → 隐私与安全性 → 开发者模式**，打开开关。iPad 会重启，重启后再点一次“打开”。

## 第三步：安装或更新 DayDayUp

1. 从 GitHub 仓库的 Releases 页面下载最新的 `DayDayUp.ipa`。
2. 把它放到**英文路径**，例如 `C:\Users\你的用户名\Downloads\DayDayUp.ipa`。路径里有中文时，AltServer 会报 “The app could not be found”（错误 1005）。
3. 按住 **Shift**，点任务栏右下角的 AltServer 图标，选 **Sideload .ipa**，再选你的 iPad。
4. 选第 2 步的 ipa，输入签名专用 Apple ID，等安装完成。
5. 如果这一版会改数据格式（发布说明里会写），安装前先在 App 里做一次完整备份。

> 如果 AltStore 里能正常登录，也可以在 AltStore → My Apps → “+” 里装，AltStore 会在后台自动续签。现在这台电脑上 AltStore 登录不成功，所以用上面的方法。

## 第四步：导入内容包

内容包是 `.ecopack` 文件，一个文件装一期（或半期）的文章、音频和词卡。

- **方法 A（推荐，已实测）：iTunes 文件共享。** iTunes → 点 iPad 图标 → 文件共享 → DayDayUp → 添加文件… → 选 `.ecopack`。对话框里可以直接粘贴中文路径。然后在 iPad 上打开 DayDayUp（已经开着就回到主屏幕再点开），它会自动导入。
- **方法 B：在 App 里选。** DayDayUp → 书架 → 右上角“导入内容包” → 选文件（可以多选）。

导入成功的文件会移到“文件”App 的 **我的 iPad › DayDayUp › 已导入**。确认书架里文章都在以后，可以删掉它们省空间。

---

## 每周六例行（约 20 分钟）

1. 电脑上按第三步重装一次。这一步同时完成 7 天续签；有新版时装的就是新版。
2. 用 iTunes 文件共享放入本周的内容包，打开 App 自动导入。
3. 在 App 里 **设置 → 数据与备份 → 立即完整备份**，存到“文件”App 或 iCloud 云盘。

- 签名过期以后，图标还在但打不开。**不要删除 App**，删除会清掉内容包、学习记录和录音。重装一次就好。
- 重装要用同一个 Apple ID。换账号签名，iPad 会把它当成另一个 App。
- 免费账号同时最多 3 个自签 App（AltStore 占 1 个）。

## V0.2 能做什么

- **书架与听读**：逐词高亮、盲听、单句循环、A–B 循环、逐句暂停、0.5–1.5× 变速、循环间隔、逐段译文、点词看词卡、句子解析、报错。
- **跟读（听后模仿）**：一次一句，听原句 → 录音 → A/B 对照。每次录音都保存，第一次录音时才请求麦克风权限。
- **雅思基础说写**：口语准备 30 秒、说 45 秒；写作 5–10 分钟、3–5 句。先自评四个维度，再看参考。写作完成后原稿只读，改写成新版本。老师或 Claude 的意见可以手动录入。题目和参考答案是 DayDayUp 原创的。
- **完整备份**：`.ddubackup` 文件里有学习记录、跟读和口语录音、写作作品。V0.1 的旧备份（.json）也能恢复。
- **诊断日志**：设置 → 诊断 → 导出诊断日志。文件在“文件”App 的 我的 iPad › DayDayUp › 诊断，也能用 iTunes 文件共享取到电脑上。

---

## 常见问题

| 现象 | 原因 | 怎么办 |
|---|---|---|
| AltServer 报 The app could not be found（1005） | ipa 所在路径有中文 | 把 ipa 复制到英文路径再装 |
| AltStore 里登录提示 Apple ID 或密码不正确 | 原因未查清：账号输错，或代理软件影响 | 先用第三步的 Shift + Sideload 方法 |
| 打开 App 提示“不受信任的开发者” | 还没信任签名账号 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| 点图标没反应，或提示 App 已不可用 | 7 天签名到期 | 按第三步重装；不要删除 App |
| 跟读页说麦克风权限已关闭 | 第一次问时点了“不允许” | 设置 → 隐私与安全性 → 麦克风 → 打开 DayDayUp |
| 录音只保存了一部分，标着“被打断” | 录音时来电话、叫了 Siri，或切出了 App | 正常现象，录音已保存；需要的话再录一次 |
| 导入失败，提示“文件校验失败” | 文件没拷完整 | 重新拷一次这个 `.ecopack` |
| 书架里一期只有一半文章 | 那一期的另一个文件还没导入 | 把同一期的两个文件都导入 |

## 这个仓库里有什么

- `DayDayUp/`：App 源代码（SwiftUI，iPadOS 26 起）。
- `project.yml`：XcodeGen 配置。GitHub 的 macOS 机器用它生成 Xcode 工程，所以不需要自己的 Mac。
- `.github/workflows/build.yml`：每次推送到 main 分支就自动编译，产出未签名的 DayDayUp.ipa，发布到 Releases。安装时用你的 Apple ID 签名。
- 仓库里没有任何杂志内容。内容包只放在你的电脑和 iPad 上，只供个人学习。雅思题目和参考答案是原创的。
