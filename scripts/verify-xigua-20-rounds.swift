import Foundation

final class NetworkManager {
    struct StringResponse: Sendable {
        let text: String
        let finalURL: URL
    }

    static let shared = NetworkManager()

    func getStringResponse(
        from _: String,
        headers _: [String: String]? = nil,
        timeout _: Int? = nil,
        maxRetries _: Int = 0
    ) async throws -> StringResponse {
        throw CocoaError(.fileReadUnknown)
    }

    func getDataPrefix(
        from _: String,
        headers _: [String: String] = [:],
        timeout _: Int? = nil,
        maxBytes _: Int
    ) async throws -> Data {
        throw CocoaError(.fileReadUnknown)
    }
}

@main
struct VerifyXiguaTwentyRounds {
    private static let baseURL = URL(string: "https://svip.xgplay20.com/2026-08-28/46765_-CyPFsFT8GKpq6t7si/3000k/hls/mixed.m3u8")!

    private static func manifest() -> (content: String, signatures: [String: String]) {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-TARGETDURATION:6"
        ]
        var signatures: [String: String] = [:]
        var sequence = 0

        func addGroup(
            _ name: String,
            durations: [Double],
            signature: String,
            discontinuity: Bool
        ) {
            if discontinuity { lines.append("#EXT-X-DISCONTINUITY") }
            for duration in durations {
                sequence += 1
                let url = "https://svip.xgplay20.com/2026-08-28/46765_-CyPFsFT8GKpq6t7si/3000k/hls/\(name)-\(sequence).ts?hash=\(sequence)"
                lines.append(String(format: "#EXTINF:%.3f,", duration))
                lines.append(url)
                signatures[url] = signature
            }
        }

        addGroup(
            "main-a",
            durations: Array(repeating: 4.0, count: 900),
            signature: "main",
            discontinuity: false
        )
        addGroup(
            "ad",
            durations: [4.0, 4.0, 3.0],
            signature: "ad",
            discontinuity: true
        )
        addGroup(
            "main-b",
            durations: Array(repeating: 4.0, count: 900),
            signature: "main",
            discontinuity: true
        )
        addGroup(
            "main-c",
            durations: Array(repeating: 4.0, count: 300),
            signature: "main",
            discontinuity: true
        )
        addGroup(
            "main-d",
            durations: [4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 2.0],
            signature: "main",
            discontinuity: true
        )
        // A second occurrence makes the short alternate SPS a repeated variant,
        // but this trailing group is unbounded and must remain in the playlist.
        addGroup(
            "tail",
            durations: [1.0],
            signature: "ad",
            discontinuity: true
        )
        lines.append("#EXT-X-ENDLIST")
        return (lines.joined(separator: "\n"), signatures)
    }

    private static func duration(of content: String) -> Double {
        content
            .split(whereSeparator: \.isNewline)
            .filter { $0.uppercased().hasPrefix("#EXTINF:") }
            .compactMap { line in
                line.dropFirst("#EXTINF:".count)
                    .split(separator: ",", maxSplits: 1)
                    .first
                    .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            }
            .reduce(0, +)
    }

    static func main() {
        let fixture = manifest()
        let originalDuration = duration(of: fixture.content)
        precondition(abs(originalDuration - 8_478.0) < 0.01, "fixture must represent 2:21:18")

        var normalizedOutputs = Set<String>()
        for round in 1...20 {
            let result = M3U8ManifestPurifier.purify(
                baseURL: baseURL,
                content: fixture.content,
                segmentSignatures: fixture.signatures
            )
            let filteredDuration = duration(of: result.content)
            precondition(
                result.removedSegmentCount == 3,
                "round \(round): expected exactly three ad segments, got \(result.removedSegmentCount)"
            )
            precondition(
                abs(filteredDuration - 8_467.0) < 0.01,
                "round \(round): expected 2:21:07, got \(filteredDuration)"
            )
            precondition(
                filteredDuration > 8_455.0,
                "round \(round): safety guard must not reach the 2:20:55 over-delete window"
            )
            precondition(
                result.content.contains("tail-") && result.content.contains("#EXT-X-ENDLIST"),
                "round \(round): trailing content must remain playable"
            )
            normalizedOutputs.insert(result.content)
        }
        precondition(normalizedOutputs.count == 1, "20 parser restarts must be deterministic")
        print("XIGUA 20-ROUND PURIFICATION REGRESSION PASSED: 2:21:18 -> 2:21:07")
    }
}
