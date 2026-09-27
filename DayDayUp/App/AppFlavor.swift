import Foundation

/// The test build is the same app under another bundle id ("….test", name "DDU测试"): iOS gives it its own
/// data container, so testing never touches the learner's real records.
enum AppFlavor {
    static let bundleId = Bundle.main.bundleIdentifier ?? ""
    static let isTest = bundleId.hasSuffix(".test")
    static let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "DayDayUp"
}
