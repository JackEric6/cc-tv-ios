import Foundation

actor DanmakuLocalCache {
    private struct Entry: Codable, Sendable {
        let updatedAt: Date
        let cues: [DanmuCue]
    }

    private let fileURL: URL
    private let lifetime: TimeInterval
    private let maximumEntries: Int
    private let maximumTotalCues: Int
    private var entries: [String: Entry]

    init(
        fileURL: URL? = nil,
        lifetime: TimeInterval = 30 * 24 * 60 * 60,
        maximumEntries: Int = 80,
        maximumTotalCues: Int = 250_000
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.lifetime = lifetime
        self.maximumEntries = maximumEntries
        self.maximumTotalCues = maximumTotalCues
        if let data = try? Data(contentsOf: self.fileURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        } else {
            entries = [:]
        }
    }

    func cues(for key: String, now: Date = Date()) -> [DanmuCue]? {
        prune(now: now)
        return entries[key]?.cues
    }

    func store(_ cues: [DanmuCue], for key: String, now: Date = Date()) {
        guard !key.isEmpty, !cues.isEmpty else { return }
        entries[key] = Entry(updatedAt: now, cues: cues)
        prune(now: now)
        persist()
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-lifetime)
        entries = entries.filter { $0.value.updatedAt >= cutoff && !$0.value.cues.isEmpty }
        let ordered = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }
        var retained: [String: Entry] = [:]
        var totalCues = 0
        for (key, entry) in ordered {
            guard retained.count < maximumEntries,
                  totalCues + entry.cues.count <= maximumTotalCues else { continue }
            retained[key] = entry
            totalCues += entry.cues.count
        }
        if retained.count != entries.count {
            entries = retained
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = fileURL
            try? mutableURL.setResourceValues(values)
        } catch {
            // Cache failures must never affect playback or danmaku loading.
        }
    }

    private static func defaultFileURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent("CongcongTV", isDirectory: true)
            .appendingPathComponent("danmaku-cross-source-v1.json")
    }
}
