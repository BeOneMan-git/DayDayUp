import XCTest

/// Fixture lookup for both `swift test` (Bundle.module + Fixtures/) and the Xcode test bundle
/// (JSON copied into the bundle root).
enum TestFixtures {
    static func url(name: String, ext: String) throws -> URL {
        let bundle = fixtureBundle()
        if let found = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: ext) {
            return found
        }
        struct Missing: Error, CustomStringConvertible {
            var description: String
        }
        throw Missing(description: "找不到测试数据 \(name).\(ext)")
    }
}

#if SWIFT_PACKAGE
private func fixtureBundle() -> Bundle { Bundle.module }
#else
private final class FixtureAnchor: NSObject {}
private func fixtureBundle() -> Bundle { Bundle(for: FixtureAnchor.self) }
#endif
