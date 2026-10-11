import Foundation

final class NetworkManager {
    struct StringResponse {
        let text: String
        let finalURL: URL
    }

    static let shared = NetworkManager()
    private(set) var requestCount = 0
    private(set) var requestedURLs: [String] = []
    private(set) var requestedTimeouts: [Int?] = []
    private(set) var requestedRetryCounts: [Int] = []
    private var responses: [String: String] = [:]
    private var finalURLs: [String: String] = [:]

    func configure(responses: [String: String], finalURLs: [String: String] = [:]) {
        requestCount = 0
        requestedURLs = []
        requestedTimeouts = []
        requestedRetryCounts = []
        self.responses = responses
        self.finalURLs = finalURLs
    }

    func getStringResponse(
        from url: String,
        headers: [String: String]? = nil,
        timeout: Int? = nil,
        maxRetries: Int = 3
    ) async throws -> StringResponse {
        requestCount += 1
        requestedURLs.append(url)
        requestedTimeouts.append(timeout)
        requestedRetryCounts.append(maxRetries)
        guard let response = responses[url] else { throw CocoaError(.fileReadUnknown) }
        guard let finalURL = URL(string: finalURLs[url] ?? url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return StringResponse(text: response, finalURL: finalURL)
    }
}

@main
struct VerifyM3U8Purifier {
    static func main() async throws {
        let manifest = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:8
        #EXTINF:6.0,
        https://cdn.example/video/0001.ts
        #EXTINF:6.0,
        https://cdn.example/video/0002.ts
        #EXT-X-CUE-OUT:DURATION=12
        #EXTINF:6.0,
        https://ads.example/ad/001.ts
        #EXTINF:6.0,
        https://ads.example/ad/002.ts
        #EXT-X-CUE-IN
        #EXTINF:6.0,
        https://cdn.example/video/0003.ts
        #EXT-X-ENDLIST
        """
        .replacingOccurrences(of: "        ", with: "")

        let result = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: manifest
        )
        precondition(result.removedSegmentCount == 2)
        precondition(result.content.contains("https://cdn.example/video/0001.ts"))
        precondition(result.content.contains("https://cdn.example/video/0003.ts"))
        precondition(!result.content.contains("ads.example"))
        precondition(result.content.contains("#EXT-X-ENDLIST"))

        let normalManifest = [
            "#EXTM3U",
            "#EXT-X-TARGETDURATION:6",
            "#EXTINF:6.0,",
            "https://cdn.example/video/0001.ts",
            "#EXTINF:6.0,",
            "https://cdn.example/video/0002.ts",
            "#EXT-X-ENDLIST"
        ].joined(separator: "\n")
        let normalResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: normalManifest
        )
        precondition(normalResult.removedSegmentCount == 0)
        precondition(normalResult.content == normalManifest)

        var minorityLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6"]
        for index in 1...8 {
            minorityLines.append("#EXTINF:6.0,")
            minorityLines.append(String(format: "https://cdn.example/video/segment%04d.ts", index))
        }
        for index in 1...2 {
            minorityLines.append("#EXTINF:6.0,")
            minorityLines.append(String(format: "https://ads.example/ad/ad%04d.ts", index))
        }
        minorityLines.append("#EXT-X-ENDLIST")
        let minorityResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: minorityLines.joined(separator: "\n")
        )
        precondition(minorityResult.removedSegmentCount == 2)
        precondition((1...8).allSatisfy {
            minorityResult.content.contains(String(format: "segment%04d.ts", $0))
        })
        precondition(!minorityResult.content.contains("ads.example"))

        var tokenizedLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6"]
        for index in 1...8 {
            tokenizedLines.append("#EXTINF:6.0,")
            tokenizedLines.append(String(format: "https://cdn.example/video/segment%04d.ts?token=main-%d", index, index))
        }
        for index in 1...2 {
            tokenizedLines.append("#EXTINF:6.0,")
            tokenizedLines.append(String(format: "https://cdn.example/video/ad%04d.ts?token=ad-%d", index, index))
        }
        tokenizedLines.append("#EXT-X-ENDLIST")
        let tokenizedResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: tokenizedLines.joined(separator: "\n")
        )
        precondition(tokenizedResult.removedSegmentCount == 2)
        precondition((1...8).allSatisfy {
            tokenizedResult.content.contains(String(format: "segment%04d.ts?token=main-%d", $0, $0))
        })
        precondition(!tokenizedResult.content.contains("ad0001.ts"))
        precondition(!tokenizedResult.content.contains("ad0002.ts"))

        var shortManifestLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6"]
        for index in 1...4 {
            shortManifestLines.append("#EXTINF:6.0,")
            shortManifestLines.append(String(format: "https://cdn.example/video/main%04d.ts", index))
        }
        shortManifestLines.append("#EXTINF:6.0,")
        shortManifestLines.append("https://cdn.example/video/ad0001.ts")
        shortManifestLines.append("#EXT-X-ENDLIST")
        let shortManifestResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: shortManifestLines.joined(separator: "\n")
        )
        precondition(shortManifestResult.removedSegmentCount == 1)
        precondition(!shortManifestResult.content.contains("ad0001.ts"))
        precondition((1...4).allSatisfy {
            shortManifestResult.content.contains(String(format: "main%04d.ts", $0))
        })

        var multiCDNLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6"]
        for index in 1...100 {
            multiCDNLines.append("#EXTINF:6.0,")
            multiCDNLines.append(String(format: "https://cdn.example/video/main-%04d-segment.ts", index))
        }
        for index in 1...20 {
            multiCDNLines.append("#EXTINF:6.0,")
            multiCDNLines.append(String(format: "https://mirror.example/video/alt-%04d-segment.ts", index))
        }
        multiCDNLines.append("#EXT-X-ENDLIST")
        let multiCDNManifest = multiCDNLines.joined(separator: "\n")
        let multiCDNResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: multiCDNManifest
        )
        precondition(multiCDNResult.removedSegmentCount == 0)
        precondition(multiCDNResult.content == multiCDNManifest)

        var rollbackLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6"]
        for index in 1...2 {
            rollbackLines.append("#EXTINF:6.0,")
            rollbackLines.append(String(format: "https://cdn.example/video/normal%04d.ts", index))
        }
        rollbackLines.append("#EXT-X-CUE-OUT:DURATION=36")
        for index in 1...6 {
            rollbackLines.append("#EXTINF:6.0,")
            rollbackLines.append(String(format: "https://cdn.example/video/ad%04d.ts", index))
        }
        rollbackLines.append("#EXT-X-CUE-IN")
        for index in 3...4 {
            rollbackLines.append("#EXTINF:6.0,")
            rollbackLines.append(String(format: "https://cdn.example/video/normal%04d.ts", index))
        }
        rollbackLines.append("#EXT-X-ENDLIST")
        let rollbackManifest = rollbackLines.joined(separator: "\n")
        let rollbackResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: rollbackManifest
        )
        precondition(rollbackResult.removedSegmentCount == 0)
        precondition(rollbackResult.content == rollbackManifest)
        precondition((1...4).allSatisfy {
            rollbackResult.content.contains(String(format: "normal%04d.ts", $0))
        })
        precondition((1...6).allSatisfy {
            rollbackResult.content.contains(String(format: "ad%04d.ts", $0))
        })

        precondition(M3U8PurifierSettings.defaultEnabled)

        var frameRateLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:5", "#EXT-X-DISCONTINUITY"]
        for index in 1...20 {
            frameRateLines.append("#EXTINF:4.080,")
            frameRateLines.append("https://cdn.example/video/main-\(index).ts")
        }
        frameRateLines.append("#EXT-X-DISCONTINUITY")
        for index in 1...3 {
            frameRateLines.append("#EXTINF:4.125,")
            frameRateLines.append("https://cdn.example/video/block-\(index).ts")
        }
        frameRateLines.append("#EXT-X-DISCONTINUITY")
        for index in 21...30 {
            frameRateLines.append("#EXTINF:4.080,")
            frameRateLines.append("https://cdn.example/video/main-\(index).ts")
        }
        frameRateLines.append("#EXT-X-ENDLIST")
        let frameRateResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: frameRateLines.joined(separator: "\n")
        )
        precondition(
            frameRateResult.removedSegmentCount == 3,
            "frame-rate removal count=\(frameRateResult.removedSegmentCount), adBlockPresent=\(frameRateResult.content.contains("block-1.ts"))"
        )
        precondition(!frameRateResult.content.contains("block-1.ts"))
        precondition((1...30).allSatisfy {
            frameRateResult.content.contains("main-\($0).ts")
        })

        var targetEpisodeLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6", "#EXT-X-DISCONTINUITY"]
        for index in 1...20 {
            targetEpisodeLines.append("#EXTINF:3.958,")
            targetEpisodeLines.append(String(format: "https://svip.example/video/main-%04d.ts?hash=main-%04d", index, index))
        }
        targetEpisodeLines.append("#EXT-X-DISCONTINUITY")
        targetEpisodeLines.append("#EXTINF:4.600,")
        targetEpisodeLines.append("https://svip.example/video/ad-001.ts?hash=ad-001")
        targetEpisodeLines.append("#EXTINF:5.533,")
        targetEpisodeLines.append("https://svip.example/video/ad-002.ts?hash=ad-002")
        targetEpisodeLines.append("#EXTINF:0.233,")
        targetEpisodeLines.append("https://svip.example/video/ad-003.ts?hash=ad-003")
        targetEpisodeLines.append("#EXT-X-DISCONTINUITY")
        for index in 21...30 {
            targetEpisodeLines.append("#EXTINF:3.958,")
            targetEpisodeLines.append(String(format: "https://svip.example/video/main-%04d.ts?hash=main-%04d", index, index))
        }
        targetEpisodeLines.append("#EXT-X-ENDLIST")
        let targetEpisodeResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://svip.example/video/mixed.m3u8")!,
            content: targetEpisodeLines.joined(separator: "\n")
        )
        precondition(
            targetEpisodeResult.removedSegmentCount == 3,
            "target-episode removal count=\(targetEpisodeResult.removedSegmentCount)"
        )
        precondition(!targetEpisodeResult.content.contains("ad-001.ts"))
        precondition(!targetEpisodeResult.content.contains("ad-002.ts"))
        precondition(!targetEpisodeResult.content.contains("ad-003.ts"))
        precondition((1...30).allSatisfy {
            targetEpisodeResult.content.contains(String(format: "main-%04d.ts?hash=main-%04d", $0, $0))
        })

        var configuredRuleLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6", "#EXT-X-DISCONTINUITY"]
        for index in 1...20 {
            configuredRuleLines.append("#EXTINF:4.111,")
            configuredRuleLines.append(String(format: "https://svip.example/video/segment-%04d.ts?token=main-%04d", index, index))
        }
        configuredRuleLines.append("#EXT-X-DISCONTINUITY")
        for (offset, duration) in ["4.613", "5.667", "0.239"].enumerated() {
            configuredRuleLines.append("#EXTINF:\(duration),")
            configuredRuleLines.append(String(format: "https://svip.example/video/segment-%04d.ts?token=splice-%04d", 21 + offset, 21 + offset))
        }
        configuredRuleLines.append("#EXT-X-DISCONTINUITY")
        for index in 24...33 {
            configuredRuleLines.append("#EXTINF:4.111,")
            configuredRuleLines.append(String(format: "https://svip.example/video/segment-%04d.ts?token=main-%04d", index, index))
        }
        configuredRuleLines.append("#EXT-X-ENDLIST")
        let configuredRuleManifest = configuredRuleLines.joined(separator: "\n")
        let configuredRule = M3U8HostRule(hosts: ["svip.example"], regex: ["-0.239"])
        let configuredRuleResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://svip.example/video/mixed.m3u8")!,
            content: configuredRuleManifest,
            hostRules: [configuredRule]
        )
        precondition(configuredRuleResult.removedSegmentCount == 3)
        precondition((1...20).allSatisfy {
            configuredRuleResult.content.contains(String(format: "segment-%04d.ts?token=main-%04d", $0, $0))
        })
        precondition(!configuredRuleResult.content.contains("token=splice-0022"))
        let nonMatchingHostResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://other.example/video/mixed.m3u8")!,
            content: configuredRuleManifest,
            hostRules: [configuredRule]
        )
        precondition(nonMatchingHostResult.removedSegmentCount == 0)
        precondition(nonMatchingHostResult.content == configuredRuleManifest)

        var finalPrecisionLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:5", "#EXT-X-DISCONTINUITY"]
        for index in 1...20 {
            finalPrecisionLines.append("#EXTINF:4.080,")
            finalPrecisionLines.append("https://cdn.example/video/main-\(index).ts")
        }
        finalPrecisionLines.append("#EXT-X-DISCONTINUITY")
        for index in 1...3 {
            finalPrecisionLines.append("#EXTINF:4.08,")
            finalPrecisionLines.append("https://cdn.example/video/tail-\(index).ts")
        }
        finalPrecisionLines.append("#EXT-X-ENDLIST")
        let finalPrecisionResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: finalPrecisionLines.joined(separator: "\n")
        )
        precondition(finalPrecisionResult.removedSegmentCount == 0)
        precondition((1...3).allSatisfy { finalPrecisionResult.content.contains("tail-\($0).ts") })

        var finalFrameRateLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:5", "#EXT-X-DISCONTINUITY"]
        for index in 1...20 {
            finalFrameRateLines.append("#EXTINF:4.080,")
            finalFrameRateLines.append("https://cdn.example/video/main-\(index).ts")
        }
        finalFrameRateLines.append("#EXT-X-DISCONTINUITY")
        for index in 1...3 {
            finalFrameRateLines.append("#EXTINF:4.125,")
            finalFrameRateLines.append("https://cdn.example/video/tail-\(index).ts")
        }
        finalFrameRateLines.append("#EXT-X-ENDLIST")
        let finalFrameRateResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: finalFrameRateLines.joined(separator: "\n")
        )
        precondition(finalFrameRateResult.removedSegmentCount == 0)
        precondition((1...3).allSatisfy { finalFrameRateResult.content.contains("tail-\($0).ts") })

        let ambiguousFrameRateLines = frameRateLines.map { line in
            line.replacingOccurrences(of: "4.080", with: "4.040")
                .replacingOccurrences(of: "4.125", with: "4.042")
        }
        let ambiguousFrameRateResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: ambiguousFrameRateLines.joined(separator: "\n")
        )
        precondition(ambiguousFrameRateResult.removedSegmentCount == 0)
        precondition(ambiguousFrameRateResult.content.contains("block-1.ts"))

        // Android's cleanUniformDurationGroups rule: repeated short blocks
        // with a different, uniform cadence are removed only when the main
        // cadence is dominant and the removal remains within safety limits.
        var uniformLines = ["#EXTM3U", "#EXT-X-TARGETDURATION:6"]
        for group in 0..<7 {
            if group > 0 { uniformLines.append("#EXT-X-DISCONTINUITY") }
            for index in 0..<4 {
                uniformLines.append("#EXTINF:4.000,")
                uniformLines.append("https://cdn.example/video/main-\(group)-\(index).ts")
            }
        }
        for block in ["a", "b"] {
            uniformLines.append("#EXT-X-DISCONTINUITY")
            for index in 0..<3 {
                uniformLines.append("#EXTINF:2.000,")
                uniformLines.append("https://cdn.example/video/ad-\(block)-\(index).ts")
            }
        }
        uniformLines.append("#EXT-X-ENDLIST")
        let uniformResult = M3U8ManifestPurifier.purify(
            baseURL: URL(string: "https://cdn.example/video/index.m3u8")!,
            content: uniformLines.joined(separator: "\n")
        )
        precondition(uniformResult.removedSegmentCount == 6)
        precondition(!uniformResult.content.contains("ad-a-0.ts"))
        precondition(!uniformResult.content.contains("ad-b-0.ts"))

        let originalGuaziURL = "https://guazi.example/video/index.m3u8?token=original"
        let requestsBeforeGuazi = NetworkManager.shared.requestCount
        let guaziResult = await M3U8Purifier.shared.prepare(
            urlString: originalGuaziURL,
            headers: ["User-Agent": "Guazi"],
            sourceKey: "GuAzI"
        )
        precondition(guaziResult.url == originalGuaziURL)
        precondition(!guaziResult.didPurify && guaziResult.removedSegmentCount == 0)
        precondition(NetworkManager.shared.requestCount == requestsBeforeGuazi)

        let xiguaMasterURL = "https://svip.xgplay13.com/2025-09-30/35902_episode/index.m3u8?token=master"
        let xiguaVariantURL = "https://svip.xgplay13.com/2025-09-30/35902_episode/3000k/hls/mixed.m3u8?token=variant"
        let xiguaMaster = """
        \u{FEFF}#EXTM3U
        #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=800000,RESOLUTION=1080x608
        3000k/hls/mixed.m3u8?token=variant
        """
        .replacingOccurrences(of: "\n", with: "\r\n")
        precondition(
            M3U8ManifestParser.firstVariantURL(
                in: xiguaMaster,
                baseURL: URL(string: xiguaMasterURL)!
            )?.absoluteString == xiguaVariantURL,
            "Xigua relative variant URL or query token was not preserved"
        )

        var xiguaLines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-TARGETDURATION:8"]
        var xiguaSegmentCount = 0
        for group in 0..<173 {
            if group > 0 { xiguaLines.append("#EXT-X-DISCONTINUITY") }
            let groupSize = group < 171 ? 4 : (group == 171 ? 2 : 1)
            for offset in 0..<groupSize {
                let duration = ["4.000", "7.960", "1.160", "3.040"][offset % 4]
                let id = String(format: "%032d", xiguaSegmentCount + 1)
                let hash = String(format: "%064d", xiguaSegmentCount + 1)
                xiguaLines.append("#EXTINF:\(duration),")
                xiguaLines.append("https://svip.xgplay13.com/2025-09-30/35902_episode/3000k/hls/\(id).ts?hash=\(hash)")
                xiguaSegmentCount += 1
            }
        }
        xiguaLines.append("#EXT-X-ENDLIST")
        let xiguaManifest = xiguaLines.joined(separator: "\n")
        let xiguaFiltered = M3U8ManifestPurifier.purify(
            baseURL: URL(string: xiguaVariantURL)!,
            content: xiguaManifest
        )
        precondition(xiguaSegmentCount == 687)
        precondition(
            xiguaFiltered.removedSegmentCount == 0,
            "normal Xigua hashed segments were falsely filtered"
        )
        precondition(
            xiguaFiltered.content == xiguaManifest,
            "Xigua discontinuity groups from the same CDN path changed unexpectedly"
        )

        NetworkManager.shared.configure(responses: [
            xiguaMasterURL: xiguaMaster,
            xiguaVariantURL: xiguaManifest
        ])
        UserDefaults.standard.set(true, forKey: M3U8PurifierSettings.key)
        let xiguaPrepared = await M3U8Purifier.shared.prepare(
            urlString: xiguaMasterURL,
            headers: ["User-Agent": "Xigua test"],
            sourceKey: "xgzy"
        )
        precondition(
            NetworkManager.shared.requestedURLs == [xiguaMasterURL, xiguaVariantURL],
            "Xigua playback requested \(NetworkManager.shared.requestedURLs); expected the master and resolved media playlist"
        )
        precondition(NetworkManager.shared.requestedTimeouts.compactMap { $0 } == [5, 5])
        precondition(NetworkManager.shared.requestedRetryCounts == [0, 0])
        precondition(
            xiguaPrepared.url == xiguaMasterURL
                && !xiguaPrepared.didPurify
                && xiguaPrepared.removedSegmentCount == 0,
            "Xigua should keep the original master URL when generic Android rules find no ads"
        )

        let redirectedMasterURL = "https://origin.example/redirect/master.m3u8?ticket=one"
        let redirectedMasterFinalURL = "https://media.example/live/master.m3u8?session=two"
        let redirectedVariantURL = "https://media.example/live/720p/index.m3u8?token=three"
        let redirectedVariantFinalURL = "https://cdn.example/secure/720p/index.m3u8?token=four"
        let redirectedMaster = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720
        720p/index.m3u8?token=three
        """
        let redirectedMedia = [
            "#EXTM3U",
            "#EXT-X-TARGETDURATION:6",
            "#EXTINF:6.0,",
            "segment-1.ts",
            "#EXT-X-CUE-OUT:DURATION=6",
            "#EXTINF:6.0,",
            "ads/ad-1.ts",
            "#EXT-X-CUE-IN",
            "#EXTINF:6.0,",
            "segment-2.ts",
            "#EXT-X-ENDLIST"
        ].joined(separator: "\n")
        NetworkManager.shared.configure(
            responses: [
                redirectedMasterURL: redirectedMaster,
                redirectedVariantURL: redirectedMedia
            ],
            finalURLs: [
                redirectedMasterURL: redirectedMasterFinalURL,
                redirectedVariantURL: redirectedVariantFinalURL
            ]
        )
        let redirectedPrepared = await M3U8Purifier.shared.prepare(
            urlString: redirectedMasterURL,
            headers: [:],
            sourceKey: "ffzy"
        )
        precondition(
            NetworkManager.shared.requestedURLs == [redirectedMasterURL, redirectedVariantURL],
            "Relative variant must be resolved against the redirected master URL: \(NetworkManager.shared.requestedURLs)"
        )
        precondition(redirectedPrepared.didPurify, "Cue-marked ad segment should be removed")
        let (proxiedData, _) = try await URLSession.shared.data(from: URL(string: redirectedPrepared.url)!)
        let proxiedPlaylist = String(decoding: proxiedData, as: UTF8.self)
        precondition(
            proxiedPlaylist.contains("https://cdn.example/secure/720p/segment-1.ts"),
            "Relative media URI must use the redirected variant URL as its base: \(proxiedPlaylist)"
        )
        precondition(!proxiedPlaylist.contains("ads/ad-1.ts"), "Purified playlist must not retain the ad segment")
        print("M3U8 PURIFIER AND PLAYBACK SAFETY CHECKS PASSED")
    }
}
