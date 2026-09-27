import Foundation

/// The test build is the same app under another bundle id (com.daydayup.app.test, name "DDU测试"): iOS gives it
/// its own data container, so testing never touches the learner's real records. AltServer appends the signing
/// team to the id when it installs ("com.daydayup.app.test.<TEAM>"), so the check looks at the start of the id.
enum AppFlavor {
    static let bundleId = Bundle.main.bundleIdentifier ?? ""
    static let isTest = bundleId.hasPrefix("com.daydayup.app.test")
    static let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "DayDayUp"
}
