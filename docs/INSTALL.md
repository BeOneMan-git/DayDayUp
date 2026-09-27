# DayDayUp 安装与使用说明（V0.1 听读版）

这份说明带你把 DayDayUp 装到 iPad 上。整个过程分四步：装 AltStore、装 DayDayUp、导入内容包、每 7 天续签。前两步只做一次，大约要 30–40 分钟。

- 电脑：你现在用的 Windows 电脑
- iPad：iPad Pro 12.9 英寸（第三代），iPadOS 26.7
- 账号：一个专门用来签名的 Apple ID（建议新注册一个，不用你的主账号）
- 一根能传数据的 USB 线

> 为什么要这样装：DayDayUp 不上架 App Store，只给你自己用。免费 Apple ID 可以给自己装的 App 签名，但签名只管 7 天，所以要靠 AltStore 定期续签。

---

## 第一步：在 Windows 上装 iTunes、iCloud 和 AltServer（只做一次）

1. 如果电脑上装过“微软商店”版的 iTunes 或 iCloud，先把它们卸载。AltServer 只认苹果官网的版本。
2. 从苹果官网下载并安装 iTunes（64 位）和 iCloud。下载链接在 AltStore 的官方说明里：
   <https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows>
3. 在同一个页面下载 AltServer 安装包（altinstaller.zip）。解压以后，运行里面的 Setup.exe。
4. 在开始菜单里搜索 “AltServer”，右键选“以管理员身份运行”。防火墙弹窗时，允许它访问专用网络。
5. 用数据线把 iPad 连到电脑。iPad 要保持解锁。iPad 问“要信任此电脑吗”时，点“信任”。
6. 打开 iTunes，点左上角的 iPad 图标，勾选“通过 Wi-Fi 与此 iPad 同步”，再点“应用”。这样以后不插线也能续签。

## 第二步：把 AltStore 装到 iPad 上（只做一次）

1. 点 Windows 任务栏右下角的 AltServer 图标，选 **Install AltStore**，再选你的 iPad。
2. 输入那个专用 Apple ID 和密码。这个账号只用来签名。
3. 在 iPad 上打开 **设置 → 通用 → VPN 与设备管理**，点你的 Apple ID，再点“信任”。
4. 打开 **设置 → 隐私与安全性 → 开发者模式**，把开关打开。iPad 会重启。重启以后，系统会再问一次，点“打开”。
5. 打开 AltStore，进入 Settings，用同一个专用 Apple ID 登录。

## 第三步：安装 DayDayUp

1. 在 iPad 上用 Safari 打开这个页面（把“你的用户名”换成你的 GitHub 用户名）：
   `https://github.com/你的用户名/DayDayUp/releases/latest`
2. 点页面里的 **DayDayUp.ipa** 下载。文件会存进“文件”App 的“下载”文件夹。
3. 打开 AltStore，进入 **My Apps**，点左上角的 **+**，选刚下载的 DayDayUp.ipa。等进度走完。
4. 主屏幕上出现 DayDayUp 图标，就装好了。

## 第四步：导入内容包

内容包是 `.ecopack` 文件，一个文件装一期（或半期）的文章、音频和词卡。9 月 4 期一共 6 个文件：09-05 和 09-12 各拆成两个，因为我往你电脑上传文件时，单个文件不能超过 20 MB。App 会把同一期的两个文件合在一起显示。

任选一种方法：

- **方法 A（推荐）：用 iTunes 文件共享。** iTunes → 点 iPad 图标 → 文件共享 → DayDayUp → 把 6 个 `.ecopack` 拖进去。打开 DayDayUp，它会自动导入。
- **方法 B：用 iCloud 云盘。** 把 `.ecopack` 放进电脑上的 iCloud 云盘文件夹。在 iPad 的“文件”App 里点一下它，选“用 DayDayUp 打开”。
- **方法 C：在 App 里选。** DayDayUp → 书架 → 右上角“导入内容包” → 选文件（可以多选）。

导入成功的文件会被移到“文件”App 里的 **我的 iPad › DayDayUp › 已导入**。确认书架里文章都在以后，可以删掉它们，省一点空间。

---

## 每 7 天续签

- 免费 Apple ID 签的 App，7 天后会过期，图标还在但打不开。
- **自动续签**：电脑开着 AltServer，iPad 和电脑连同一个 Wi-Fi，AltStore 会在后台自己续。
- **手动续签**：打开 AltStore → My Apps → **Refresh All**。
- 过期不会丢数据。续签以后打开，学习记录都还在。
- 免费账号的限制：同时最多 3 个自签 App（AltStore 自己占 1 个）；每 7 天最多注册 10 个 App ID。

> 升级条件：如果 4 周里有 2 次以上因为续签问题停学，就改用苹果开发者计划（99 美元/年）加 TestFlight。代码不用改。

## 更新 DayDayUp

1. 每次代码更新，GitHub 会自动编译出新的 DayDayUp.ipa，放在 Releases 页面。
2. 在 iPad 上下载新的 ipa，在 AltStore 里用 **+** 再装一次。新版会覆盖旧版，学习记录保留。

## 备份学习记录

- 学习记录（进度、生词本、认识的词、听读时长）只存在这台 iPad 上。
- **设置 → 数据与备份 → 立即备份**，把备份存进“文件”App 或 iCloud 云盘。建议每周一次；超过 7 天没备份，“今日”页会提醒你。
- 换 iPad 或重装 App 以后：**设置 → 数据与备份 → 从备份恢复**。

---

## 常见问题

| 现象 | 原因 | 怎么办 |
|---|---|---|
| 打开 App 提示“无法验证 App”或“不受信任的开发者” | 还没信任签名账号 | 设置 → 通用 → VPN 与设备管理 → 点你的 Apple ID → 信任 |
| 点图标没反应，或提示 App 已不可用 | 7 天签名过期了 | 打开 AltStore → My Apps → Refresh All |
| AltServer 找不到 iPad | iTunes 没连上，或不在同一网络 | 先插线确认 iTunes 能看到 iPad；打开“通过 Wi-Fi 同步”；AltServer 用管理员身份运行 |
| 导入失败，提示“文件校验失败”或“文件不完整” | 文件没拷完整 | 重新拷一次这个 `.ecopack` |
| 书架里一期只有一半文章 | 那一期的另一个文件还没导入 | 把同一期的两个文件都导入 |

## 这个仓库里有什么

- `DayDayUp/`：App 源代码（SwiftUI，iPadOS 26 起）。
- `project.yml`：XcodeGen 配置。GitHub 的 macOS 机器用它生成 Xcode 工程，所以不需要自己的 Mac。
- `.github/workflows/build.yml`：每次推送到 main 分支就自动编译，产出未签名的 DayDayUp.ipa，发布到 Releases。AltStore 安装时会用你的 Apple ID 签名。
- 仓库里没有任何杂志内容。内容包只放在你的电脑和 iPad 上，只供个人学习。
