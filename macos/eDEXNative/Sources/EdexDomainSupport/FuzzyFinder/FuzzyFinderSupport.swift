import Foundation

public enum FuzzyMatcher {
    /// Case-insensitive substring match over selectable filesystem rows,
    /// preserving legacy order inside prefix/non-prefix buckets.
    public static func search(_ items: [FilesystemItem], query: String, limit: Int = 5) -> [FilesystemItem] {
        let normalizedQuery = query.lowercased()
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }

        let matches = items
            .filter { item in
                item.role != .showDisks && item.role != .goUp
            }
            .filter { item in
                guard !normalizedQuery.isEmpty else { return true }
                return item.name.lowercased().contains(normalizedQuery)
            }

        var prefixMatches: [FilesystemItem] = []
        var substringMatches: [FilesystemItem] = []
        for item in matches {
            if item.name.lowercased().hasPrefix(normalizedQuery) {
                prefixMatches.append(item)
            } else {
                substringMatches.append(item)
            }
        }
        return Array((prefixMatches + substringMatches).prefix(cappedLimit))
    }
}

public enum FuzzySelection {
    public static func next(from index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = index + 1
        return next >= 0 && next < count ? next : 0
    }

    public static func previous(from index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let previous = index - 1
        return previous >= 0 && previous < count ? previous : 0
    }
}

public enum FuzzyTerminalInput {
    public static func quotedPath(_ path: String) -> String {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escapedPath)'"
    }
}
