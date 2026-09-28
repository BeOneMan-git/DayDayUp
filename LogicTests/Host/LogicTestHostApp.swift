import SwiftUI

// Host used only so XCTest can run inside an iPad Simulator.
// DayDayUp stays on iPadOS 26 and is not the host: a lower deployment target
// lets the same tests launch when the runner's newest iPad runtime is older than 26.
// This app is not installed on the physical iPad.
@main
struct LogicTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            Color.clear
        }
    }
}
