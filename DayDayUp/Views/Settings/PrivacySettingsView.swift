import SwiftUI
import UIKit

/// 隐私 (PLAT-12, ACC-29): the app has no network code and never uploads; files leave the iPad only when the
/// learner exports, shares or copies them. Says what each export contains and what it leaves out, and shows the
/// microphone permission with a way to the app's page in the iPad's Settings.
struct PrivacySettingsView: View {
    @Environment(RecorderService.self) private var recorder
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var mic = MicrophoneStatus.notAsked

    var body: some View {
        Form {
            networkSection
            backupSection
            weeklySection
            diagnosticsSection
            clipboardSection
            microphoneSection
        }
        .navigationTitle("隐私")
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        recorder.refreshPermission()
        mic = MicrophoneStatus.current()
    }

    // MARK: Network

    private var networkSection: some View {
        Section {
            SettingsNoteRow(symbol: "wifi.slash", title: "不联网",
                            detail: "App 里没有联网的代码：不上传、不统计、不同步。断网时所有功能照常。")
            SettingsNoteRow(symbol: "internaldrive", title: "数据在哪里",
                            detail: "学习记录、录音和作文只存在这台 iPad 上的 App 里。")
            SettingsNoteRow(symbol: "hand.raised", title: "什么时候离开 iPad",
                            detail: "只有你自己导出、分享或复制的时候。App 从不自动发送。")
        } header: {
            Text("网络")
        }
    }

    // MARK: Exports

    private var backupSection: some View {
        Section {
            included("学习记录（听读进度、生词和词汇复习、计划、练习时间、理解题）、全部录音（跟读、口语、词汇朗读）、写作原文和每一版改写、你录入的反馈和笔记、各项设置。")
            included("你练过的句子和词条出处的原句：一句一句存着，没有整篇文章。")
            excluded("内容包（文章、音频、词库）和诊断日志。")
        } header: {
            Text("完整备份（.ddubackup）")
        } footer: {
            Text("在“设置 › 备份与恢复 › 立即完整备份”里导出。导出前会先列出数量，保存到哪里由你选。")
        }
    }

    private var weeklySection: some View {
        Section {
            included(WeeklyExport.included.joined(separator: "、") + "。")
            excluded(WeeklyExport.excluded.joined(separator: "、") + "。")
        } header: {
            Text("周报（JSON、CSV、PDF）")
        } footer: {
            Text("在“进度”页的周报里导出，导出前也会列出这些。")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            included("App 版本、设备型号和系统版本、内容包和各种记录的数量、音频线路（耳机或扬声器）、麦克风权限。")
            included("操作记录：打开 App、导入、备份、录音开始和结束、收藏的词和词群、出错信息。")
            included("你提交的“报错”：那一句原文和你写的说明。")
            excluded("录音、作文、整篇文章。")
        } header: {
            Text("诊断日志（.txt）")
        } footer: {
            Text("在“设置 › 关于与使用说明”里导出。文件先存在“文件”App 的 我的 iPad › DayDayUp › 诊断，你分享它时才离开 iPad。")
        }
    }

    private var clipboardSection: some View {
        Section {
            included("题目、用时，和你写下的文字（作文或笔记）。")
            excluded("录音。")
        } header: {
            Text("复制给 Claude（剪贴板）")
        } footer: {
            Text("只放进剪贴板；贴到哪里由你决定。")
        }
    }

    private func included(_ text: String) -> some View {
        Label {
            Text("有：" + text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Theme.accent)
        }
    }

    private func excluded(_ text: String) -> some View {
        Label {
            Text("没有：" + text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "xmark.circle")
                .foregroundStyle(Color.secondary)
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        Section {
            SettingsNoteRow(symbol: mic.symbol, title: "麦克风：" + mic.text, detail: mic.detail)
            Button {
                openAppSettings()
            } label: {
                Label("打开 iPad 设置里的 DayDayUp 页", systemImage: "gear")
            }
        } header: {
            Text("权限")
        } footer: {
            Text("在那一页可以改麦克风和通知。改完回到 App，这里会更新。")
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
