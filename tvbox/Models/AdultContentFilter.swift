import Foundation
import Combine

/// 成人内容过滤规则。过滤只作用于搜索结果和分类浏览结果。
enum AdultContentFilter {
    private static let markerPattern = #"(伦理片|理论片|伦理|情色|成人|限制级|18\s*\+)"#
    private static let markerRegex = try! NSRegularExpression(pattern: markerPattern, options: [.caseInsensitive])
    private static let noiseRegex = try! NSRegularExpression(
        pattern: #"(?i)(4k|2k|1080p|2160p|720p|高清|超清|蓝光|蓝光原盘|国语|粤语|中字|双语|全集|全\s*\d+\s*集)"#,
        options: []
    )

    static func isAdultContent(_ video: Movie.Video) -> Bool {
        [video.name, video.type, video.category, video.vodTypeName]
            .contains { containsMarker($0) }
    }

    static func containsMarker(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return markerRegex.firstMatch(in: value, range: range) != nil
    }

    /// 归一化采集站标题，保留季数/部数等作品身份信息。
    static func normalizeName(_ value: String) -> String {
        var normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        normalized = replace(noiseRegex, in: normalized, with: "")
        normalized = replace(markerRegex, in: normalized, with: "")
        normalized = normalized.unicodeScalars
            .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
        return normalized
    }

    /// 同时返回完整标题键和去掉成人标记后的作品键，支持跨源标题差异。
    static func titleKeys(_ value: String) -> Set<String> {
        let raw = normalizeName(value)
        let stripped = normalizeName(replace(markerRegex, in: value, with: ""))
        return Set([raw, stripped].filter { $0.count >= 2 })
    }

    static func collectAdultTitleKeys(from videos: [Movie.Video]) -> Set<String> {
        videos.filter(isAdultContent).reduce(into: Set<String>()) { keys, video in
            keys.formUnion(titleKeys(video.name))
        }
    }

    static func filtered(_ videos: [Movie.Video], enabled: Bool) -> [Movie.Video] {
        guard enabled else { return videos }
        let adultKeys = collectAdultTitleKeys(from: videos)
        return videos.filter { video in
            guard !isAdultContent(video) else { return false }
            return titleKeys(video.name).isDisjoint(with: adultKeys)
        }
    }

    private static func replace(_ regex: NSRegularExpression, in value: String, with replacement: String) -> String {
        regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }
}

@MainActor
final class AdultContentFilterSession: ObservableObject {
    static let shared = AdultContentFilterSession()

    /// nil 表示使用默认开启状态；false 仅在当前进程内关闭。
    @Published private(set) var sessionFilterAdult: Bool?

    var isEnabled: Bool { sessionFilterAdult ?? true }

    func disableForCurrentSession() {
        sessionFilterAdult = false
    }
}
