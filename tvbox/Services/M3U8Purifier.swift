import Foundation
import Network

struct M3U8HostRule: Sendable {
    let hosts: [String]
    let regex: [String]
}

enum M3U8ManifestParser {
    static func firstVariantURL(in content: String, baseURL: URL) -> URL? {
        let lines = content
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for index in lines.indices where lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("#EXT-X-STREAM-INF") {
            for candidateLine in lines.dropFirst(index + 1) {
                let candidate = candidateLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty, !candidate.hasPrefix("#"), Self.isM3U8URI(candidate) else {
                    continue
                }
                return URL(string: candidate, relativeTo: baseURL)?.absoluteURL
            }
        }
        return nil
    }

    private static func isM3U8URI(_ value: String) -> Bool {
        let path = value.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return path.lowercased().hasSuffix(".m3u8")
    }
}

/// Android 版 M3u8.purify 的 iOS 实现。
///
/// 净化结果只在进程内保存，并通过回环 HTTP 地址交给 KSPlayer。播放清单中的
/// 分片、密钥和子资源会被改写成绝对地址，因此播放器不需要额外的代理能力。
actor M3U8Purifier {
    static let shared = M3U8Purifier()

    struct PreparedURL: Sendable {
        let url: String
        let didPurify: Bool
        let removedSegmentCount: Int
    }

    private let network = NetworkManager.shared
    private let proxy = M3U8LoopbackProxy.shared
    private var hostRules: [M3U8HostRule] = []

    func updateHostRules(_ rules: [M3U8HostRule]) {
        hostRules = rules
    }

    func prepare(urlString: String, headers: [String: String], sourceKey: String) async -> PreparedURL {
        let normalizedSource = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedSource != "guazi",
              !["jianpian", "fan_jianpian", "fan_jp"].contains(normalizedSource) else {
            return PreparedURL(url: urlString, didPurify: false, removedSegmentCount: 0)
        }
        guard M3U8PurifierSettings.isEnabled,
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              Self.isHTTPURL(url),
              Self.looksLikeM3U8(url),
              !url.absoluteString.localizedCaseInsensitiveContains("url="),
              !Self.isLoopbackURL(url) else {
            return PreparedURL(url: urlString, didPurify: false, removedSegmentCount: 0)
        }

        do {
            let firstResponse = try await network.getStringResponse(
                from: url.absoluteString,
                headers: headers.isEmpty ? nil : headers,
                timeout: 5,
                maxRetries: 0
            )
            let firstContent = Self.normalizeManifest(firstResponse.text)
            guard firstContent.hasPrefix("#EXTM3U") else {
                return PreparedURL(url: urlString, didPurify: false, removedSegmentCount: 0)
            }

            let targetURL: URL
            let content: String
            if let variant = M3U8ManifestParser.firstVariantURL(in: firstContent, baseURL: firstResponse.finalURL) {
                let variantResponse = try await network.getStringResponse(
                    from: variant.absoluteString,
                    headers: headers.isEmpty ? nil : headers,
                    timeout: 5,
                    maxRetries: 0
                )
                targetURL = variantResponse.finalURL
                content = Self.normalizeManifest(variantResponse.text)
            } else {
                targetURL = firstResponse.finalURL
                content = firstContent
            }

            let result = M3U8ManifestPurifier.purify(
                baseURL: targetURL,
                content: content,
                hostRules: hostRules
            )
            guard result.removedSegmentCount > 0,
                  let proxyURL = try? await proxy.publish(content: result.content) else {
                // Keep the original URL when no filtering occurred. Replacing a
                // master playlist with its first variant can drop query tokens
                // and bypass the player's normal variant selection.
                return PreparedURL(url: urlString, didPurify: false, removedSegmentCount: 0)
            }
            return PreparedURL(
                url: proxyURL,
                didPurify: true,
                removedSegmentCount: result.removedSegmentCount
            )
        } catch {
            // 净化是增强能力，网络失败不能阻断原始播放链路。
            return PreparedURL(url: urlString, didPurify: false, removedSegmentCount: 0)
        }
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func isLoopbackURL(_ url: URL) -> Bool {
        ["127.0.0.1", "localhost", "::1"].contains(url.host?.lowercased() ?? "")
    }

    private static func looksLikeM3U8(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return value.contains(".m3u8") || url.pathExtension.lowercased() == "m3u"
    }

    private static func normalizeManifest(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct M3U8PurifierSettings {
    static let key = "m3u8_purify"
    static let defaultEnabled = true

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            defaults.set(defaultEnabled, forKey: key)
            return defaultEnabled
        }
        return defaults.bool(forKey: key)
    }
}

/// 只服务净化后的 m3u8 文本，不代理分片数据。
actor M3U8LoopbackProxy {
    static let shared = M3U8LoopbackProxy()

    private struct Slot {
        let content: String
        var lastAccess: UInt64
    }

    private let queue = DispatchQueue(label: "com.congcong.tv.m3u8-proxy")
    private var listener: NWListener?
    private var port: UInt16?
    private var sequence: UInt64 = 0
    private var slots: [String: Slot] = [:]
    private var readyWaiters: [CheckedContinuation<UInt16, Error>] = []
    private let slotLimit = 8

    func publish(content: String) async throws -> String {
        let port = try await startIfNeeded()
        sequence &+= 1
        let key = "\(UInt64(Date().timeIntervalSince1970 * 1000))-\(sequence)"
        slots[key] = Slot(content: content, lastAccess: sequence)
        trimSlots()
        return "http://127.0.0.1:\(port)/m3u8/\(key).m3u8"
    }

    private func startIfNeeded() async throws -> UInt16 {
        if let port { return port }
        return try await withCheckedThrowingContinuation { continuation in
            readyWaiters.append(continuation)
            guard listener == nil else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let newListener = try NWListener(using: parameters)
                listener = newListener
                newListener.stateUpdateHandler = { [weak self] state in
                    Task { await self?.handleListenerState(state) }
                }
                newListener.newConnectionHandler = { [weak self] connection in
                    Task { await self?.accept(connection) }
                }
                newListener.start(queue: queue)
            } catch {
                listener = nil
                resumeReadyWaiters(with: error)
            }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                listener?.cancel()
                listener = nil
                resumeReadyWaiters(with: CocoaError(.fileReadUnknown))
                return
            }
            self.port = port
            resumeReadyWaiters(with: nil)
        case .failed(let error):
            listener?.cancel()
            listener = nil
            port = nil
            resumeReadyWaiters(with: error)
        case .cancelled:
            listener = nil
            port = nil
        default:
            break
        }
    }

    private func resumeReadyWaiters(with error: Error?) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else if let port {
                waiter.resume(returning: port)
            } else {
                waiter.resume(throwing: CocoaError(.fileReadUnknown))
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, data: Data())
    }

    private func receive(on connection: NWConnection, data accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task {
                await self?.handleRequest(
                    data: data,
                    complete: complete,
                    error: error,
                    connection: connection,
                    accumulated: accumulated
                )
            }
        }
    }

    private func handleRequest(
        data: Data?,
        complete: Bool,
        error: NWError?,
        connection: NWConnection,
        accumulated: Data
    ) {
        guard error == nil else {
            connection.cancel()
            return
        }
        let request = accumulated + (data ?? Data())
        let delimiter = Data([13, 10, 13, 10])
        guard let range = request.range(of: delimiter) else {
            guard !complete, request.count < 65_536 else {
                send(Self.response(status: 400, reason: "Bad Request", body: "Bad Request"), on: connection)
                return
            }
            receive(on: connection, data: request)
            return
        }

        let headerData = request[..<range.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8),
              let line = header.components(separatedBy: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              line.hasPrefix("GET ") else {
            send(Self.response(status: 400, reason: "Bad Request", body: "Bad Request"), on: connection)
            return
        }

        let pathString = String(path)
        let key = pathString
            .replacingOccurrences(of: "/m3u8/", with: "")
            .replacingOccurrences(of: ".m3u8", with: "")
        guard pathString.hasPrefix("/m3u8/"), let slot = slots[key] else {
            send(Self.response(status: 404, reason: "Not Found", body: "m3u8 slot not found"), on: connection)
            return
        }
        sequence &+= 1
        slots[key] = Slot(content: slot.content, lastAccess: sequence)
        send(Self.response(status: 200, reason: "OK", body: slot.content, contentType: "application/vnd.apple.mpegurl"), on: connection)
    }

    private func trimSlots() {
        guard slots.count > slotLimit else { return }
        let removeCount = slots.count - slotLimit
        for key in slots.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }).prefix(removeCount).map(\.key) {
            slots.removeValue(forKey: key)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func response(
        status: Int,
        reason: String,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) -> Data {
        let bodyData = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Cache-Control: no-store",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(header.utf8) + bodyData
    }
}

struct M3U8ManifestPurifier {
    struct Result {
        let content: String
        let removedSegmentCount: Int
    }

    private struct ParsedDuration {
        let raw: String
        let value: Double
        let precision: Int
        let fraction: String
    }

    private struct URLFilterResult {
        let content: String
        let removedSegmentCount: Int
    }

    private struct AdDateRange {
        var startOffset: Double
        var startDate: Date?
        var endDate: Date?
        var duration: Double?
        var isAd: Bool
    }

    private struct TimedSegment {
        let lines: [String]
        let duration: Double
        let startOffset: Double
        let programDateTime: Date?
        let keyState: String
        let mapState: String
    }

    private static let adURLPattern = try! NSRegularExpression(
        pattern: #"(?i)(^|[/?&=_.-])(ads?|adv|advert(ise(ment)?)?|commercial|preroll|pre-roll|midroll|mid-roll|postroll|post-roll|sponsor|scte|vast|vmap|interstitial|bumper)([/?&=_.-]|$)"#
    )
    private static let adDomains = [
        "adservice", "adserver", "adsystem", "doubleclick", "googlesyndication",
        "advertising", "2mdn.net", "moatads", "scorecardresearch", "quantserve"
    ]
    private static let frameRateFeatures = makeFrameRateFeatures()

    static func purify(
        baseURL: URL,
        content: String,
        hostRules: [M3U8HostRule] = []
    ) -> Result {
        let original = normalize(content)
        guard original.hasPrefix("#EXTM3U") else { return Result(content: content, removedSegmentCount: 0) }
        let originalSegments = mediaCount(original)
        // AVBox 的 get() 会先把所有可播放 URI 解析成绝对地址。
        // 代理清单运行在 127.0.0.1 上，若保留相对地址，播放器会错误地向回环地址请求分片。
        let resolved = resolveMediaURIs(resolveURIAttributes(original, baseURL: baseURL), baseURL: baseURL)
        let urlFilter = removeURLMinority(resolved, baseURL: baseURL)
        // 与 AVBox 一致：URL 过滤没有命中时，从原清单继续执行标记和分组净化。
        var transformed = urlFilter.removedSegmentCount > 0 ? urlFilter.content : resolved
        var removed = urlFilter.removedSegmentCount
        transformed = removeConfiguredAdRules(
            transformed,
            baseURL: baseURL,
            hostRules: hostRules,
            removed: &removed
        )
        transformed = removeTimedAdRanges(transformed, removed: &removed)
        transformed = removeCommonAdMarkers(transformed, removed: &removed)
        if hasEndList(transformed) && transformed.contains("#EXT-X-DISCONTINUITY") {
            transformed = removeDecimalPrecisionGroups(transformed, removed: &removed)
            transformed = removeFrameRateGroups(transformed, removed: &removed)
            transformed = removeUniformDurationGroups(transformed, removed: &removed)
        }
        transformed = removeSuspiciousDiscontinuityGroups(transformed, removed: &removed)
        transformed = normalizeDiscontinuities(transformed)

        if originalSegments > 0 && Double(removed) > Double(originalSegments) * 0.5 {
            return Result(content: original, removedSegmentCount: 0)
        }
        guard removed > 0, isPlayable(transformed) else {
            return Result(content: original, removedSegmentCount: 0)
        }
        if hasEndList(original) && !hasEndList(transformed) {
            transformed += "#EXT-X-ENDLIST\n"
        }
        return Result(content: transformed, removedSegmentCount: removed)
    }

    private static func normalize(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func resolveURIAttributes(_ content: String, baseURL: URL) -> String {
        let pattern = try! NSRegularExpression(pattern: #"URI="([^"]+)""#)
        return content.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            guard line.hasPrefix("#"), let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let resolved = URL(string: String(line[valueRange]), relativeTo: baseURL)?.absoluteString else {
                return line
            }
            return line.replacingCharacters(in: valueRange, with: resolved)
        }.joined(separator: "\n")
    }

    private static func resolveMediaURIs(_ content: String, baseURL: URL) -> String {
        content.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return line }
            return absoluteURL(trimmed, baseURL: baseURL)
        }.joined(separator: "\n")
    }

    private static func removeURLMinority(_ content: String, baseURL: URL) -> URLFilterResult {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let urls = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var prefixes: [String: Int] = [:]
        var hosts: [String: Int] = [:]
        for raw in urls {
            let absolute = absoluteURL(raw, baseURL: baseURL)
            if let prefix = mediaURLPrefix(absolute) {
                prefixes[prefix, default: 0] += 1
            }
            if let host = mediaHost(absolute) { hosts[host, default: 0] += 1 }
        }
        let dominantPrefix = prefixes.max(by: { $0.value < $1.value })
        let prefixedURLCount = prefixes.values.reduce(0, +)
        let usePrefix = dominantPrefix.map {
            prefixes.count > 1 && prefixedURLCount > 0
                && Double($0.value) / Double(prefixedURLCount) >= 0.8
        } ?? false
        let dominantHost = hosts.max(by: { $0.value < $1.value })
        let allHostsExceedNoAdThreshold = hosts.values.allSatisfy { $0 > 15 }
        let useHost = !usePrefix && !allHostsExceedNoAdThreshold
            && (dominantHost.map { hosts.count > 1 && Double($0.value) / Double(urls.count) >= 0.8 } ?? false)
        guard usePrefix || useHost else {
            return URLFilterResult(content: content, removedSegmentCount: 0)
        }

        var pending: [String] = []
        var output: [String] = []
        var removed = 0
        for raw in lines {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty { pending.append(raw); continue }
            if item.hasPrefix("#") {
                if isSegmentTag(item) { pending.append(raw) } else { output.append(contentsOf: pending); pending.removeAll(); output.append(raw) }
                continue
            }
            let absolute = absoluteURL(raw, baseURL: baseURL)
            let prefix = mediaURLPrefix(absolute)
            let host = mediaHost(absolute) ?? ""
            let keep = usePrefix
                ? (prefix.map { $0.hasPrefix(dominantPrefix?.key ?? "") } ?? false)
                : (host == dominantHost?.key || (hosts[host] ?? 0) > 15)
            if keep {
                output.append(contentsOf: pending); pending.removeAll(); output.append(absolute)
            } else {
                pending.removeAll(); removed += 1
            }
        }
        output.append(contentsOf: pending)
        // AVBox 会放弃这一步可疑的 URL 过滤，再对原清单运行后续净化规则。
        guard Double(removed) <= Double(urls.count) * 0.3 else {
            return URLFilterResult(content: content, removedSegmentCount: 0)
        }
        return URLFilterResult(
            content: output.joined(separator: "\n"),
            removedSegmentCount: removed
        )
    }

    private static func mediaURLPrefix(_ rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return nil
        }
        let path = components.percentEncodedPath
        guard let slash = path.lastIndex(of: "/"),
              let extensionDot = path.lastIndex(of: "."),
              extensionDot > slash else {
            return nil
        }
        let stem = String(path[..<extensionDot])
        guard stem.count > 4 else { return nil }
        let prefix = String(stem.dropLast(4))
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(prefix)"
    }

    private static func mediaHost(_ rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    private static func removeCommonAdMarkers(_ content: String, removed: inout Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var pending: [String] = []
        var inAdBreak = false
        var cueAdEndOffset: Double?
        var adDiscontinuity = false
        var elapsed = 0.0
        for raw in lines {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty { pending.append(raw); continue }
            if item.hasPrefix("#") {
                if item.uppercased().hasPrefix("#EXT-X-CUE-IN") {
                    if inAdBreak || pending.contains(where: { isAdSignal($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                        inAdBreak = false
                        cueAdEndOffset = nil
                        pending = adDiscontinuity ? ["#EXT-X-DISCONTINUITY"] : []
                        adDiscontinuity = false
                    }
                    continue
                }
                if isCueOutTag(item) {
                    output.append(contentsOf: pending); pending.removeAll()
                    inAdBreak = true
                    cueAdEndOffset = cueBreakEndOffset(item, elapsed: elapsed)
                    adDiscontinuity = false
                    continue
                }
                if isAdSignal(item) {
                    output.append(contentsOf: pending); pending.removeAll()
                    inAdBreak = true
                    cueAdEndOffset = nil
                    adDiscontinuity = false
                    pending.append(raw)
                    continue
                }
                if isStandaloneAdTag(item) {
                    output.append(contentsOf: pending); pending.removeAll()
                    continue
                }
                if inAdBreak && isDiscontinuityTag(item) { adDiscontinuity = true }
                if inAdBreak && item.uppercased() == "#EXT-X-ENDLIST" {
                    output.append(item)
                    inAdBreak = false
                    cueAdEndOffset = nil
                    pending.removeAll()
                    continue
                }
                if isSegmentTag(item) || inAdBreak { pending.append(raw) }
                else { output.append(contentsOf: pending); pending.removeAll(); output.append(raw) }
                continue
            }
            let duration = pendingSegmentDuration(pending)
            if inAdBreak || pending.contains(where: { isAdSignal($0) }) || isAdURL(item) {
                pending.removeAll()
                removed += 1
                elapsed += duration
                if let cueEndOffset = cueAdEndOffset, elapsed >= cueEndOffset {
                    inAdBreak = false
                    cueAdEndOffset = nil
                    pending = adDiscontinuity ? ["#EXT-X-DISCONTINUITY"] : []
                    adDiscontinuity = false
                }
                continue
            }
            output.append(contentsOf: pending); pending.removeAll(); output.append(raw)
            elapsed += duration
        }
        if !inAdBreak { output.append(contentsOf: pending) }
        return output.joined(separator: "\n")
    }

    private static func removeTimedAdRanges(_ content: String, removed: inout Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var headers: [String] = []
        var pending: [String] = []
        var trailing: [String] = []
        var segments: [TimedSegment] = []
        var activeKey = ""
        var activeMap = ""
        var elapsed = 0.0
        var programDateTime: Date?
        var seenSegment = false
        var adDateRanges: [String: AdDateRange] = [:]
        var scteAdStart: Double?
        var scteAdIntervals: [(start: Double, end: Double)] = []

        for raw in lines {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.uppercased().hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                if let colon = item.firstIndex(of: ":") {
                    programDateTime = parseDate(String(item[item.index(after: colon)...]))
                }
            }
            if item.uppercased().hasPrefix("#EXT-X-DATERANGE:") {
                let attributes = attributeList(item)
                if let id = attributes["ID"], !id.isEmpty {
                    var range = adDateRanges[id] ?? AdDateRange(
                        startOffset: elapsed,
                        startDate: nil,
                        endDate: nil,
                        duration: nil,
                        isAd: false
                    )
                    if let value = attributes["START-DATE"], let date = parseDate(value) { range.startDate = date }
                    if let value = attributes["END-DATE"], let date = parseDate(value) { range.endDate = date }
                    if let value = attributes["DURATION"], let duration = Double(value), duration > 0 { range.duration = duration }
                    range.isAd = range.isAd || isAdDateRange(attributes)
                    adDateRanges[id] = range
                }
                if attributes["SCTE35-OUT"] != nil, scteAdStart == nil { scteAdStart = elapsed }
                if attributes["SCTE35-IN"] != nil, let start = scteAdStart {
                    scteAdIntervals.append((start: start, end: elapsed))
                    scteAdStart = nil
                }
            }
            if item.uppercased().hasPrefix("#EXT-X-KEY:") { activeKey = raw }
            if item.uppercased().hasPrefix("#EXT-X-MAP:") { activeMap = raw }

            guard !item.isEmpty, !item.hasPrefix("#") else {
                if !seenSegment && !isSegmentScopedTag(item) {
                    headers.append(raw)
                } else if seenSegment && item == "#EXT-X-ENDLIST" {
                    trailing.append(raw)
                } else {
                    pending.append(raw)
                }
                continue
            }

            let duration = pending.compactMap(parseDuration).last?.value ?? 0
            segments.append(TimedSegment(
                lines: pending + [raw],
                duration: duration,
                startOffset: elapsed,
                programDateTime: programDateTime,
                keyState: activeKey,
                mapState: activeMap
            ))
            seenSegment = true
            elapsed += duration
            if let currentProgramDateTime = programDateTime {
                programDateTime = currentProgramDateTime.addingTimeInterval(duration)
            }
            pending.removeAll()
        }
        if seenSegment { trailing.append(contentsOf: pending) }
        else { headers.append(contentsOf: pending) }
        guard !segments.isEmpty else { return content }

        var remove = Set<Int>()
        let firstTimedSegment = segments.first(where: { $0.programDateTime != nil })
        for range in adDateRanges.values where range.isAd {
            let duration = range.startDate.flatMap { start in
                range.endDate.map { $0.timeIntervalSince(start) }
            } ?? range.duration
            guard let duration, duration > 0 else { continue }
            var startOffset = range.startOffset
            if let startDate = range.startDate,
               let firstTimedSegment,
               let firstDate = firstTimedSegment.programDateTime {
                startOffset = firstTimedSegment.startOffset + startDate.timeIntervalSince(firstDate)
            }
            for (index, segment) in segments.enumerated()
            where segment.startOffset < startOffset + duration && segment.startOffset + segment.duration > startOffset {
                remove.insert(index)
            }
        }
        for interval in scteAdIntervals where interval.end > interval.start {
            for (index, segment) in segments.enumerated()
            where segment.startOffset < interval.end && segment.startOffset + segment.duration > interval.start {
                remove.insert(index)
            }
        }
        guard !remove.isEmpty else { return content }

        var output = headers
        var keyState = ""
        var mapState = ""
        for (index, segment) in segments.enumerated() {
            guard !remove.contains(index) else { continue }
            keyState = appendState(output: &output, tag: "#EXT-X-KEY", current: keyState, next: segment.keyState)
            mapState = appendState(output: &output, tag: "#EXT-X-MAP", current: mapState, next: segment.mapState)
            output.append(contentsOf: segment.lines.filter {
                let line = $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return !line.hasPrefix("#EXT-X-KEY:") && !line.hasPrefix("#EXT-X-MAP:")
            })
        }
        output.append(contentsOf: trailing)
        removed += remove.count
        return output.joined(separator: "\n")
    }

    private static func isSegmentScopedTag(_ line: String) -> Bool {
        let upper = line.uppercased()
        if upper.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") { return false }
        return [
            "#EXTINF:", "#EXT-X-BYTERANGE", "#EXT-X-PROGRAM-DATE-TIME:",
            "#EXT-X-DISCONTINUITY", "#EXT-X-PART:", "#EXT-X-PRELOAD-HINT:",
            "#EXT-X-KEY:", "#EXT-X-MAP:", "#EXT-X-DATERANGE:", "#EXT-X-CUE-",
            "#EXT-X-SCTE", "#EXT-OATCLS-SCTE", "#EXT-X-ASSET", "#EXT-X-AD", "#EXT-X-VMAP"
        ].contains(where: upper.hasPrefix)
    }

    private static func attributeList(_ line: String) -> [String: String] {
        let body: String
        if let colon = line.firstIndex(of: ":") {
            body = String(line[line.index(after: colon)...])
        } else {
            body = line
        }
        let pattern = try! NSRegularExpression(pattern: #"(?:^|,)\s*([A-Z0-9-]+)=((?:"[^"]*")|[^,]*)"#, options: [.caseInsensitive])
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var result: [String: String] = [:]
        for match in pattern.matches(in: body, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: body),
                  let valueRange = Range(match.range(at: 2), in: body) else { continue }
            let value = String(body[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            result[String(body[keyRange]).uppercased()] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return result
    }

    private static func isAdDateRange(_ attributes: [String: String]) -> Bool {
        let marker = "\(attributes["ID"] ?? "") \(attributes["CLASS"] ?? "")"
        return isAdLikeText(marker) || attributes["SCTE35-OUT"] != nil || attributes["SCTE35-IN"] != nil ||
            attributes["X-ASSET-URI"] != nil || attributes["X-ASSET-LIST"] != nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ]
        for options in optionSets {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func appendState(output: inout [String], tag: String, current: String, next: String) -> String {
        guard current != next else { return current }
        if !next.isEmpty { output.append(next) }
        else if tag == "#EXT-X-KEY", !current.isEmpty { output.append("#EXT-X-KEY:METHOD=NONE") }
        return next
    }

    private static func isCueOutTag(_ line: String) -> Bool {
        let upper = line.uppercased()
        return upper.hasPrefix("#EXT-X-CUE-OUT:") || upper == "#EXT-X-CUE-OUT" ||
            upper.hasPrefix("#EXT-X-CUE-OUT-CONT:")
    }

    private static func cueBreakEndOffset(_ line: String, elapsed: Double) -> Double? {
        let attributes = attributeList(line)
        let rawDurationPattern = try! NSRegularExpression(
            pattern: #"^#EXT-X-CUE-OUT:\s*([\d.]+)"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let rawDuration = rawDurationPattern.firstMatch(in: line, range: range).flatMap { match in
            Range(match.range(at: 1), in: line).flatMap { Double(line[$0]) }
        }
        let duration = attributes["DURATION"].flatMap(Double.init) ?? rawDuration
        guard let duration, duration > 0 else { return nil }
        let elapsedTime = attributes["ELAPSEDTIME"].flatMap(Double.init) ?? 0
        return elapsed + max(0, duration - elapsedTime)
    }

    private static func pendingSegmentDuration(_ lines: [String]) -> Double {
        lines.compactMap(parseDuration).last?.value ?? 0
    }

    private static func removeConfiguredAdRules(
        _ content: String,
        baseURL: URL,
        hostRules: [M3U8HostRule],
        removed: inout Int
    ) -> String {
        let host = baseURL.host?.lowercased() ?? ""
        let configuredRules = hostRules
            .filter { rule in
            rule.hosts.contains { host.contains($0.lowercased()) }
            }
            .flatMap(\.regex)
        guard !configuredRules.isEmpty else { return content }

        // ApiConfig only registers Android M3u8.isAd() rules for this path.
        // Keep that distinction here so ordinary parse/filter rules are never
        // interpreted as playlist-ad patterns.
        let rules = configuredRules.filter(isConfiguredAdRule)
        guard !rules.isEmpty else { return content }

        var result = content
        var durationRules: [String] = []
        for rule in rules {
            if rule.contains("#EXT-X-DISCONTINUITY") || rule.contains("#EXTINF") {
                result = removeRegexMatchedGroups(result, pattern: rule, removed: &removed)
            } else if let value = Double(rule), value != 0 {
                durationRules.append(rule)
            }
        }
        if !durationRules.isEmpty {
            result = removeDurationMatchedGroups(result, rules: durationRules, removed: &removed)
        }
        return result
    }

    private static func isConfiguredAdRule(_ rule: String) -> Bool {
        let value = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if let number = Double(value) { return number != 0 }
        return [
            "#EXT-X-DISCONTINUITY", "#EXTINF", "#EXT-X-ENDLIST", "#EXT-X-KEY",
            "#EXT-X-CUE-OUT", "#EXT-X-CUE-IN", "#EXT-X-DATERANGE"
        ].contains(where: value.contains)
    }

    private static func removeRegexMatchedGroups(
        _ content: String,
        pattern: String,
        removed: inout Int
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return content
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: range)
        guard !matches.isEmpty else { return content }

        var result = content
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let block = String(result[matchRange])
            removed += mediaCount(block)
            result.replaceSubrange(
                matchRange,
                with: block.replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")
            )
        }
        return result
    }

    private static func removeDurationMatchedGroups(
        _ content: String,
        rules: [String],
        removed: inout Int
    ) -> String {
        let groups = buildGroups(normalize(content).components(separatedBy: "\n"))
        guard groups.count > 1 else { return content }

        var output: [String] = []
        for group in groups {
            let hasBoundary = group.contains {
                isDiscontinuityTag($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let durations = group.compactMap(parseDuration)
            guard hasBoundary, !durations.isEmpty else {
                output.append(contentsOf: group)
                continue
            }

            let total = durations.reduce(Decimal.zero) { partial, duration in
                partial + (Decimal(string: duration.raw) ?? .zero)
            }
            let totalText = NSDecimalNumber(decimal: total).stringValue
            let isAd = rules.contains { rule in
                if rule.hasPrefix("-") {
                    let lastDuration = durations.last.flatMap { Decimal(string: $0.raw) }
                    let ruleDuration = Decimal(string: String(rule.dropFirst()))
                    guard let lastDuration, let ruleDuration else { return false }
                    return NSDecimalNumber(decimal: lastDuration).stringValue
                        .hasPrefix(NSDecimalNumber(decimal: ruleDuration).stringValue)
                }
                let firstDuration = durations.first.flatMap { Decimal(string: $0.raw) }
                let ruleDuration = Decimal(string: rule)
                let firstMatches = firstDuration.flatMap { duration in
                    ruleDuration.map {
                        NSDecimalNumber(decimal: duration).stringValue
                            .hasPrefix(NSDecimalNumber(decimal: $0).stringValue)
                    }
                } ?? false
                let totalMatches = ruleDuration.map {
                    totalText.hasPrefix(NSDecimalNumber(decimal: $0).stringValue)
                } ?? totalText.hasPrefix(rule)
                return firstMatches || totalMatches
            }
            if isAd {
                removed += mediaCount(group.joined(separator: "\n"))
            } else {
                output.append(contentsOf: group)
            }
        }
        return output.joined(separator: "\n")
    }

    private static func removeSuspiciousDiscontinuityGroups(_ content: String, removed: inout Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var groups: [[String]] = [[]]
        for line in lines {
            if isDiscontinuityTag(line.trimmingCharacters(in: .whitespacesAndNewlines)),
               groups.last?.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") }) == true {
                groups.append([])
            }
            groups[groups.count - 1].append(line)
        }
        guard groups.count >= 3 else { return content }
        let stats = groups.map(groupStats)
        guard let mainIndex = stats.indices.max(by: { groupScore(stats[$0]) < groupScore(stats[$1]) }) else { return content }
        let main = stats[mainIndex]
        guard main.segments >= 3 else { return content }
        var output: [String] = []
        for index in groups.indices {
            let current = stats[index]
            let short = current.segments > 0 && (current.segments <= 2 || current.duration < main.duration * 0.18)
            let different = !main.host.isEmpty && !current.host.isEmpty && main.host != current.host
            let differentPath = !main.path.isEmpty && !current.path.isEmpty && main.path != current.path
            let cadenceOutlier = isBoundedCadenceOutlier(groups: groups, index: index, segmentCount: current.segments)
            let adLike = current.adLike || different || (current.segments <= 2 && differentPath) || cadenceOutlier
            if index != mainIndex && short && adLike {
                removed += current.segments
            } else {
                output.append(contentsOf: groups[index])
            }
        }
        return output.joined(separator: "\n")
    }

    private static func isBoundedCadenceOutlier(groups: [[String]], index: Int, segmentCount: Int) -> Bool {
        guard index > 0, index + 1 < groups.count, (3...12).contains(segmentCount) else { return false }
        let candidate = groups[index].compactMap(parseDuration).map(\.value)
        guard candidate.count == segmentCount,
              let candidateMedian = median(candidate),
              candidate.allSatisfy({ abs($0 - candidateMedian) <= 0.05 }) else { return false }

        let before = Array(groups[index - 1].compactMap(parseDuration).map(\.value).suffix(12))
        let after = Array(groups[index + 1].compactMap(parseDuration).map(\.value).prefix(12))
        guard before.count >= 3, after.count >= 3,
              let beforeMedian = median(before),
              let afterMedian = median(after),
              abs(beforeMedian - afterMedian) <= 0.04 else { return false }
        return abs(candidateMedian - (beforeMedian + afterMedian) / 2) >= 0.08
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func removeDecimalPrecisionGroups(_ content: String, removed: inout Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let groups = buildGroups(lines)
        guard groups.count >= 2 else { return content }
        let durations = groups.flatMap { $0.compactMap(parseDuration) }
        let precisions = durations.map(\.precision)
        let precisionCounts = Dictionary(grouping: precisions, by: { $0 }).mapValues(\.count)
        guard durations.count >= 8, precisionCounts.count >= 2,
              let dominantPrecision = precisionCounts.max(by: { $0.value < $1.value }),
              Double(dominantPrecision.value) / Double(durations.count) >= 0.7 else { return content }

        var drop = Set<Int>()
        var removable = 0
        for index in groups.indices.dropLast() {
            let groupDurations = groups[index].compactMap(parseDuration)
            let segmentCount = mediaCount(groups[index].joined(separator: "\n"))
            guard !groupDurations.isEmpty, segmentCount > 0, segmentCount <= 12,
                  groupDurations.allSatisfy({ $0.precision != dominantPrecision.key }) else { continue }
            if segmentCount <= adSegmentLimit(for: durations) {
                drop.insert(index)
                removable += segmentCount
            }
        }
        guard !drop.isEmpty, removable <= adSegmentLimit(for: durations),
              Double(removable) <= Double(durations.count) * 0.3 else { return content }
        var output: [String] = []
        for index in groups.indices {
            if drop.contains(index) { removed += mediaCount(groups[index].joined(separator: "\n")) }
            else { output.append(contentsOf: groups[index]) }
        }
        return output.joined(separator: "\n")
    }

    private static func removeFrameRateGroups(_ content: String, removed: inout Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let groups = buildGroups(lines)
        guard groups.count >= 2,
              let masterFrameRate = dominantFrameRate(groups.flatMap { $0 }) else { return content }

        var drop = Set<Int>()
        var removable = 0
        for index in groups.indices.dropLast() {
            let segmentCount = mediaCount(groups[index].joined(separator: "\n"))
            guard segmentCount > 0, segmentCount <= 12 else { continue }
            var matched = 0
            var mismatched = 0
            for line in groups[index] {
                guard let duration = parseDuration(line) else { continue }
                let rate = exclusiveFrameRate(duration)
                if rate == masterFrameRate { matched += 1 }
                else if rate != 0 { mismatched += 1 }
            }
            if mismatched > 0 && mismatched >= matched {
                drop.insert(index)
                removable += segmentCount
            }
        }
        let durations = groups.flatMap { $0.compactMap(parseDuration) }
        guard !drop.isEmpty, removable <= adSegmentLimit(for: durations) else { return content }

        var output: [String] = []
        for index in groups.indices {
            if drop.contains(index) { removed += mediaCount(groups[index].joined(separator: "\n")) }
            else { output.append(contentsOf: groups[index]) }
        }
        return output.joined(separator: "\n")
    }

    /// Some VOD providers splice same-host ads without cue markers. Android's
    /// purifier recognizes these as short discontinuity groups whose segment
    /// durations are uniform but differ from the dominant cadence. Keep the
    /// same conservative limits here: at least three repeated main groups,
    /// at least two occurrences of the alternate cadence, and no more than
    /// the normal ad segment budget.
    private static func removeUniformDurationGroups(_ content: String, removed: inout Int) -> String {
        let groups = buildGroups(normalize(content).components(separatedBy: "\n"))
        guard groups.count >= 4 else { return content }

        var cadenceByGroup: [String?] = Array(repeating: nil, count: groups.count)
        var cadenceCounts: [String: Int] = [:]
        for index in groups.indices.dropLast() {
            guard let cadence = uniformGroupDuration(groups[index]) else { continue }
            cadenceByGroup[index] = cadence
            cadenceCounts[cadence, default: 0] += 1
        }

        guard let dominant = cadenceCounts.max(by: { $0.value < $1.value }),
              dominant.value >= 3,
              cadenceCounts.values.filter({ $0 == dominant.value }).count == 1,
              let mainDuration = Decimal(string: dominant.key) else { return content }

        var drop = Set<Int>()
        var removable = 0
        for index in groups.indices.dropLast() {
            guard let cadence = cadenceByGroup[index], cadence != dominant.key,
                  let count = cadenceCounts[cadence], count >= 2,
                  Double(count) / Double(dominant.value) <= 0.35,
                  let duration = Decimal(string: cadence),
                  duration > Decimal(string: "1")!, duration <= Decimal(string: "10")!,
                  absDecimal(duration - mainDuration) >= Decimal(string: "0.05")!,
                  groups[index].filter({ parseDuration($0) != nil }).count >= 3 else { continue }
            drop.insert(index)
            removable += mediaCount(groups[index].joined(separator: "\n"))
        }

        let totalSegments = groups.reduce(0) { $0 + mediaCount($1.joined(separator: "\n")) }
        let allDurations = groups.flatMap { $0.compactMap(parseDuration) }
        guard !drop.isEmpty,
              removable <= adSegmentLimit(for: allDurations),
              Double(removable) <= Double(max(totalSegments, 1)) * 0.3 else { return content }

        var output: [String] = []
        for index in groups.indices {
            if drop.contains(index) {
                removed += mediaCount(groups[index].joined(separator: "\n"))
            } else {
                output.append(contentsOf: groups[index])
            }
        }
        return normalizeDiscontinuities(output.joined(separator: "\n"))
    }

    private static func uniformGroupDuration(_ group: [String]) -> String? {
        let durations = group.compactMap(parseDuration)
        guard durations.count >= 3, durations.count <= 12,
              let first = durations.first,
              durations.allSatisfy({ $0.value == first.value }) else { return nil }
        return NSDecimalNumber(decimal: Decimal(string: first.raw) ?? .zero).stringValue
    }

    private static func absDecimal(_ value: Decimal) -> Decimal {
        value < .zero ? -value : value
    }

    private static func buildGroups(_ lines: [String]) -> [[String]] {
        var result: [[String]] = [[]]
        for line in lines {
            if isDiscontinuityTag(line.trimmingCharacters(in: .whitespaces)),
               result.last?.contains(where: { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }) == true {
                result.append([])
            }
            result[result.count - 1].append(line)
        }
        return result
    }

    private static func parseDuration(_ line: String) -> ParsedDuration? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#EXTINF:"),
              let raw = trimmed.dropFirst(8).split(separator: ",", maxSplits: 1).first else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard let duration = Double(value), duration.isFinite else { return nil }
        let unsigned = value.first == "-" || value.first == "+" ? String(value.dropFirst()) : value
        let components = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let fractionDigits = components.count > 1 ? String(components[1]) : ""
        let precision = components.count > 1 ? fractionDigits.count : 0
        let normalizedFraction = fractionDigits.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return ParsedDuration(
            raw: value,
            value: duration,
            precision: precision,
            fraction: normalizedFraction.isEmpty ? "0" : "0.\(normalizedFraction)"
        )
    }

    private static func dominantFrameRate(_ lines: [String]) -> Int? {
        var counts: [Int: Int] = [:]
        for line in lines {
            guard let duration = parseDuration(line) else { continue }
            let rate = exclusiveFrameRate(duration)
            if rate != 0 { counts[rate, default: 0] += 1 }
        }
        guard let item = counts.max(by: { $0.value < $1.value }), item.value >= 2,
              counts.values.filter({ $0 == item.value }).count == 1 else { return nil }
        return item.key
    }

    private static func exclusiveFrameRate(_ duration: ParsedDuration) -> Int {
        let matches = [30, 25, 24].filter { frameRateFeatures[$0]?.contains(duration.fraction) == true }
        return matches.count == 1 ? matches[0] : 0
    }

    private static func makeFrameRateFeatures() -> [Int: Set<String>] {
        [30: frameFeatures(frameRate: 30, includeNtsc: true),
         25: frameFeatures(frameRate: 25, includeNtsc: false),
         24: frameFeatures(frameRate: 24, includeNtsc: true)]
    }

    private static func frameFeatures(frameRate: Int, includeNtsc: Bool) -> Set<String> {
        var result = Set<String>()
        addFrameFeatures(denominator: frameRate, frameCount: frameRate, into: &result)
        if includeNtsc {
            addFrameFeatures(
                denominator: frameRate * 1_000,
                frameCount: frameRate * 10,
                numeratorMultiplier: 1_001,
                into: &result
            )
        }
        return result
    }

    private static func addFrameFeatures(
        denominator: Int,
        frameCount: Int,
        numeratorMultiplier: Int = 1,
        into result: inout Set<String>
    ) {
        let scale10: Int64 = 10_000_000_000
        for frame in 1...frameCount {
            let numerator = (frame * numeratorMultiplier) % denominator
            guard numerator > 0 else { continue }
            var ticks10 = (Int64(numerator) * scale10 + Int64(denominator / 2)) / Int64(denominator)
            if ticks10 >= scale10 { ticks10 = 0 }
            for precision in 3...6 {
                let scale = powerOfTen(precision)
                let roundingUnit = powerOfTen(10 - precision)
                var ticks = (ticks10 + roundingUnit / 2) / roundingUnit
                if ticks >= scale { ticks = 0 }
                guard ticks > 0 else { continue }
                let rawDigits = String(ticks % scale)
                var digits = String(repeating: "0", count: max(0, precision - rawDigits.count)) + rawDigits
                while digits.last == "0" { digits.removeLast() }
                if !digits.isEmpty { result.insert("0.\(digits)") }
            }
        }
    }

    private static func powerOfTen(_ exponent: Int) -> Int64 {
        (0..<exponent).reduce(Int64(1)) { value, _ in value * 10 }
    }

    private static func adSegmentLimit(for durations: [ParsedDuration]) -> Int {
        let totalMinutes = durations.reduce(0) { $0 + $1.value } / 60
        if totalMinutes <= 30 { return 18 }
        if totalMinutes <= 60 { return 24 }
        if totalMinutes <= 90 { return 30 }
        return 36
    }

    private struct GroupStats {
        var segments = 0
        var duration = 0.0
        var host = ""
        var path = ""
        var adLike = false
    }

    private static func groupScore(_ stats: GroupStats) -> Double {
        stats.duration > 0 ? stats.duration : Double(stats.segments)
    }

    private static func groupStats(_ lines: [String]) -> GroupStats {
        var stats = GroupStats()
        for raw in lines {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let duration = parseDuration(item) { stats.duration += duration.value }
            guard !item.isEmpty, !item.hasPrefix("#") else {
                if isAdSignal(item) || isStandaloneAdTag(item) { stats.adLike = true }
                continue
            }
            stats.segments += 1
            if isAdURL(item) { stats.adLike = true }
            if let url = URL(string: item) {
                if stats.host.isEmpty { stats.host = url.host ?? "" }
                if stats.path.isEmpty { stats.path = mediaPathPrefix(item) ?? "" }
            }
        }
        return stats
    }

    private static func mediaPathPrefix(_ rawURL: String) -> String? {
        guard var components = URLComponents(string: rawURL) else { return nil }
        let path = components.percentEncodedPath
        guard let slash = path.lastIndex(of: "/") else { return nil }
        components.percentEncodedPath = String(path[...slash])
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static func normalizeDiscontinuities(_ content: String) -> String {
        var output: [String] = []
        var seenMedia = false
        var pending = false
        for raw in normalize(content).split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.hasPrefix("#EXT-X-DISCONTINUITY") && !item.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") {
                if seenMedia { pending = true }
                continue
            }
            if pending {
                if !item.isEmpty && !item.hasPrefix("#EXT-X-ENDLIST") { output.append("#EXT-X-DISCONTINUITY") }
                pending = false
            }
            output.append(raw)
            if !item.isEmpty && !item.hasPrefix("#") { seenMedia = true }
        }
        return output.joined(separator: "\n")
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> String {
        URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL.absoluteString ?? raw
    }

    private static func isSegmentTag(_ line: String) -> Bool {
        if line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") { return false }
        return ["#EXTINF", "#EXT-X-BYTERANGE", "#EXT-X-PROGRAM-DATE-TIME", "#EXT-X-DISCONTINUITY", "#EXT-X-PART", "#EXT-X-PRELOAD-HINT"].contains { line.hasPrefix($0) }
    }

    private static func isDiscontinuityTag(_ line: String) -> Bool {
        line.hasPrefix("#EXT-X-DISCONTINUITY") && !line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE")
    }

    private static func isAdSignal(_ line: String) -> Bool {
        let value = line.lowercased()
        return value.hasPrefix("#ext-oatcls-scte35") || value.hasPrefix("#ext-x-scte35") ||
            value.hasPrefix("#ext-x-splicepoint-scte35") || value.hasPrefix("#ext-x-cue") ||
            value.hasPrefix("#ext-x-asset") || value.hasPrefix("#ext-x-vmap-ad-break") || value.hasPrefix("#ext-x-ad")
    }

    private static func isStandaloneAdTag(_ line: String) -> Bool {
        guard line.hasPrefix("#EXT-X-DATERANGE") else { return false }
        return isAdLikeText(line) || line.contains("X-ASSET-URI") || line.contains("X-ASSET-LIST")
    }

    private static func isAdLikeText(_ line: String) -> Bool {
        let value = line.lowercased()
        return ["scte", "cue", "interstitial", "vmap", "vast", "advert", "commercial", "ad-", "ad_", "ad.", "preroll", "midroll", "postroll", "bumper"].contains { value.contains($0) }
    }

    private static func isAdURL(_ line: String) -> Bool {
        let lower = line.lowercased()
        if adDomains.contains(where: lower.contains) { return true }
        let range = NSRange(lower.startIndex..., in: lower)
        return adURLPattern.firstMatch(in: lower, range: range) != nil
    }

    private static func mediaCount(_ content: String) -> Int {
        content.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") }.count
    }

    private static func hasEndList(_ content: String) -> Bool { content.contains("#EXT-X-ENDLIST") }

    private static func isPlayable(_ content: String) -> Bool {
        guard content.hasPrefix("#EXTM3U") else { return false }
        var pendingExtInf = false
        var count = 0
        for raw in content.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF") { pendingExtInf = true }
            else if !line.hasPrefix("#") { count += 1; pendingExtInf = false }
        }
        return count > 0 && !pendingExtInf
    }
}
