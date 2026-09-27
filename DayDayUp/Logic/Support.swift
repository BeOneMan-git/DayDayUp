import Foundation

// Small helpers shared by the data files. Pure Foundation, so LogicTests can compile them.

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }
    static var today: String { of(Date()) }

    /// Keys for the last n days, oldest first.
    static func lastDays(_ n: Int) -> [String] {
        let cal = Calendar.current
        let now = Date()
        return (0..<n).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: now).map(of)
        }
    }
}

// MARK: - Lossy arrays

/// Decodes anything (even null) without reading it, so the list moves past a bad item.
private struct SkipItem: Decodable {
    init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// Decodes an array but drops items that fail, so one damaged record never loses the rest.
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [T] = []
        while !list.isAtEnd {
            if let value = try? list.decode(T.self) {
                out.append(value)
            } else if (try? list.decode(SkipItem.self)) == nil {
                break
            }
        }
        return out
    }
}
