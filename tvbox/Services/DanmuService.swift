import Foundation

/// Loads and parses danmaku using the protocol shared with the Android client.
@MainActor
public final class DanmuService {
    public static let shared = DanmuService()
    public static let builtinAPI = "https://logvardanmu.konfan.cn/87654321"
    /// Android keeps this older deployment as a compatible fallback. It is
    /// intentionally raced with the primary endpoint and never blocks it.
    public static let builtinFallbackAPIs = [
        // Legacy Android deployment.
        "https://saas-oa.shyeguang.cn",
        // Public LogVar-compatible community deployment documented by the
        // upstream service. It uses the same DanDanPlay v2 routes.
        "https://api.danmu.icu"
    ]
    private static let searchRequestTimeout = 5
    private static let commentRequestTimeout = 8
    // Keep one bounded retry for transient 502/429/network handoffs without
    // making the first video frame wait behind a long retry chain.
    private static let requestRetryCount = 1
    private static let retryBaseDelay: TimeInterval = 0.35
    private static let retryMaxDelay: TimeInterval = 2.5
    private static let cacheLifetime: TimeInterval = 300

    public struct Configuration: Sendable, Equatable {
        public var apiURL: String?
        public var useDefault: Bool?

        public init(apiURL: String? = nil, useDefault: Bool? = nil) {
            self.apiURL = apiURL
            self.useDefault = useDefault
        }
    }

    private var customSession: URLSession
    private let crossSourceCache = DanmakuLocalCache()
    private var searchCache: [String: (date: Date, results: [DanmuSearchResult])] = [:]
    private var builtinSearchCache: [String: (date: Date, results: [DanmuSearchResult])] = [:]
    private var cueCache: [String: (date: Date, cues: [DanmuCue])] = [:]
    private var searchInFlight: [String: Task<[DanmuSearchResult], Error>] = [:]
    private var builtinSearchInFlight: [String: Task<[DanmuSearchResult], Error>] = [:]
    private var cueInFlight: [String: Task<[DanmuCue], Error>] = [:]
    private var loadInFlight: [String: Task<[DanmuCue], Never>] = [:]

    private init() {
        customSession = Self.makeSession()
    }

    /// Rebuild the independent danmaku session when the proxy preference changes.
    func reloadSessionForProxySetting() {
        customSession.invalidateAndCancel()
        customSession = Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        // Danmaku is independent from video-source connectivity. Waiting for a
        // stalled source request here made the search appear to fail whenever
        // a playback route was offline.
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        NetworkProxyPolicy.configure(configuration)
        return URLSession(configuration: configuration)
    }

    /// Loads a timeline. Network, parsing, cancellation, and malformed data all
    /// degrade to an empty result so playback is never blocked by danmaku.
    public func load(
        title: String,
        episode: String,
        configuration: Configuration = Configuration()
    ) async -> [DanmuCue] {
        let cacheKey = DanmakuCacheKey.make(title: title, episode: episode)
        if let cacheKey, let cached = await crossSourceCache.cues(for: cacheKey) {
            return cached
        }
        let apiURLs = resolveAutomaticAPIURLs(configuration)
        let contentKey = cacheKey ?? "\(title.lowercased())\u{1F}\(episode.lowercased())"
        let requestKey = "\(contentKey)\u{1E}\(apiURLs.map { $0.lowercased() }.joined(separator: "|"))"
        if let task = loadInFlight[requestKey] {
            return await task.value
        }
        let task = Task<[DanmuCue], Never> { @MainActor [weak self] in
            guard let self else { return [] }
            return await self.performLoad(title: title, episode: episode, apiURLs: apiURLs)
        }
        loadInFlight[requestKey] = task
        defer { loadInFlight[requestKey] = nil }
        let cues = await task.value
        if let cacheKey, !cues.isEmpty {
            await crossSourceCache.store(cues, for: cacheKey)
        }
        return cues
    }

    private func performLoad(title: String, episode: String, apiURLs: [String]) async -> [DanmuCue] {
        await firstNonEmpty(from: apiURLs) { [weak self] apiURL in
            guard let self else { return [] }
            do {
                if Self.isBuiltinAPI(apiURL) {
                    return try await self.loadBuiltin(
                        baseURL: Self.normalizeBaseURL(apiURL),
                        title: title,
                        episode: episode
                    )
                }
                let body = try await self.loadCustom(
                    apiURL: apiURL,
                    title: title,
                    episode: episode,
                    followURL: false
                )
                let directCues = try await Self.parseOffMain(body)
                if !directCues.isEmpty { return directCues }
                let results = Self.parseSearchResults(body)
                return await self.loadFirstAvailable(results, title: title, episode: episode)
            } catch {
                return []
            }
        }
    }

    /// Alias kept short for callers that prefer a fetch-style API.
    public func fetch(
        title: String,
        episode: String,
        configuration: Configuration = Configuration()
    ) async -> [DanmuCue] {
        await load(title: title, episode: episode, configuration: configuration)
    }

    /// Compatibility alias used by the native player integration.
    public func loadCues(
        title: String,
        episode: String,
        configuration: Configuration = Configuration()
    ) async -> [DanmuCue] {
        await load(title: title, episode: episode, configuration: configuration)
    }

    public func load(
        title: String,
        episode: String,
        apiURL: String?
    ) async -> [DanmuCue] {
        await load(
            title: title,
            episode: episode,
            configuration: Configuration(apiURL: apiURL)
        )
    }

    public func searchResults(
        title: String,
        episode: String,
        configuration: Configuration = Configuration()
    ) async throws -> [DanmuSearchResult] {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let apiFingerprint = resolveAPIURLs(configuration)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
        let cacheKey = "\(query.lowercased())\u{1F}\(episode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\u{1E}\(apiFingerprint)"
        if let cached = searchCache[cacheKey] {
            if Date().timeIntervalSince(cached.date) < Self.cacheLifetime {
                return cached.results
            }
        }
        // Auto-loading and the manual search panel can ask for the same title
        // at nearly the same time. Share one request instead of creating two
        // independent timeout/retry chains against the danmaku service.
        if let task = searchInFlight[cacheKey] {
            return try await task.value
        }
        let task = Task<[DanmuSearchResult], Error> { @MainActor [weak self] in
            guard let self else { return [] }
            return try await self.performSearchResults(query: query, episode: episode, configuration: configuration, cacheKey: cacheKey)
        }
        searchInFlight[cacheKey] = task
        defer { searchInFlight[cacheKey] = nil }
        return try await task.value
    }

    private func performSearchResults(
        query: String,
        episode: String,
        configuration: Configuration,
        cacheKey: String
    ) async throws -> [DanmuSearchResult] {
        let apiURLs = resolveAPIURLs(configuration)
        let uniqueResults: [DanmuSearchResult] = await firstNonEmpty(from: apiURLs) { [weak self] apiURL in
            guard let self else { return [] }
            do {
                if Self.isBuiltinAPI(apiURL) {
                    return try await self.searchBuiltinResults(
                        baseURL: Self.normalizeBaseURL(apiURL),
                        query: query,
                        episode: episode
                    )
                }
                let body = try await self.loadCustom(
                    apiURL: apiURL,
                    title: query,
                    episode: episode,
                    followURL: false
                )
                return Self.parseSearchResults(body)
            } catch {
                return []
            }
        }
        if !uniqueResults.isEmpty {
            pruneCachesIfNeeded()
            searchCache[cacheKey] = (Date(), uniqueResults)
            return uniqueResults
        }
        // Empty searches can mean a transient provider/network failure. Do not
        // turn one failed request into a cached miss for the next playback.
        return []
    }

    public func loadSearchResult(
        _ result: DanmuSearchResult,
        title: String? = nil,
        episode: String? = nil
    ) async throws -> [DanmuCue] {
        guard let url = result.url.trimmedNonEmpty else { return [] }
        let crossSourceKey = title.flatMap {
            DanmakuCacheKey.make(title: $0, episode: episode ?? "")
        }
        if let crossSourceKey,
           let cached = await crossSourceCache.cues(for: crossSourceKey) {
            return cached
        }
        if let cached = cueCache[url] {
            if Date().timeIntervalSince(cached.date) < Self.cacheLifetime {
                if let crossSourceKey {
                    await crossSourceCache.store(cached.cues, for: crossSourceKey)
                }
                return cached.cues
            }
        }
        if let task = cueInFlight[url] {
            let cues = try await task.value
            if let crossSourceKey, !cues.isEmpty {
                await crossSourceCache.store(cues, for: crossSourceKey)
            }
            return cues
        }
        let task = Task<[DanmuCue], Error> { @MainActor [weak self] in
            guard let self else { return [] }
            return try await self.performLoadSearchResult(result, cacheKey: url)
        }
        cueInFlight[url] = task
        defer { cueInFlight[url] = nil }
        let cues = try await task.value
        if let crossSourceKey, !cues.isEmpty {
            await crossSourceCache.store(cues, for: crossSourceKey)
        }
        return cues
    }

    private func performLoadSearchResult(_ result: DanmuSearchResult, cacheKey url: String) async throws -> [DanmuCue] {
        let urls = result.isBuiltin ? Self.builtinCommentURLs(for: url) : [url]
        var rateLimitedHosts = Set<String>()
        for candidateURL in urls {
            try Task.checkCancellation()
            if let host = URL(string: candidateURL)?.host?.lowercased(),
               rateLimitedHosts.contains(host) { continue }
            let body: String
            do {
                body = try await getDanmakuText(
                    from: candidateURL,
                    timeout: Self.commentRequestTimeout
                )
            } catch let error as NetworkError {
                if case .httpError(429) = error,
                   let host = URL(string: candidateURL)?.host?.lowercased() {
                    rateLimitedHosts.insert(host)
                }
                continue
            } catch {
                continue
            }
            let cues = try await Self.parseOffMain(body)
            if !cues.isEmpty {
                pruneCachesIfNeeded()
                cueCache[url] = (Date(), cues)
                return cues
            }
            if let nestedURL = Self.extractURL(from: body), nestedURL != candidateURL {
                do {
                    let nestedBody = try await getDanmakuText(
                        from: nestedURL,
                        timeout: Self.commentRequestTimeout
                    )
                    let nestedCues = try await Self.parseOffMain(nestedBody)
                    if !nestedCues.isEmpty {
                        pruneCachesIfNeeded()
                        cueCache[url] = (Date(), nestedCues)
                        return nestedCues
                    }
                } catch {
                    continue
                }
            }
        }
        // Never cache a failed/empty parse: another provider or a later retry
        // may return the valid timeline for this same episode.
        return []
    }

    private func pruneCachesIfNeeded() {
        let maxEntries = 80
        if searchCache.count >= maxEntries {
            let keys = searchCache
                .sorted { $0.value.date < $1.value.date }
                .prefix(searchCache.count - maxEntries + 1)
                .map(\.key)
            keys.forEach { searchCache.removeValue(forKey: $0) }
        }
        if builtinSearchCache.count >= maxEntries {
            let keys = builtinSearchCache
                .sorted { $0.value.date < $1.value.date }
                .prefix(builtinSearchCache.count - maxEntries + 1)
                .map(\.key)
            keys.forEach { builtinSearchCache.removeValue(forKey: $0) }
        }
        if cueCache.count >= maxEntries {
            let keys = cueCache
                .sorted { $0.value.date < $1.value.date }
                .prefix(cueCache.count - maxEntries + 1)
                .map(\.key)
            keys.forEach { cueCache.removeValue(forKey: $0) }
        }
    }

    private func loadFirstAvailable(
        _ results: [DanmuSearchResult],
        title: String,
        episode: String
    ) async -> [DanmuCue] {
        let candidates = Self.automaticLoadCandidates(results, title: title, episode: episode)
        let batchSize = 2
        for start in stride(from: 0, to: candidates.count, by: batchSize) {
            let batch = Array(candidates[start..<min(start + batchSize, candidates.count)])
            let cues = await withTaskGroup(of: [DanmuCue].self) { group in
                for result in batch {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        do {
                            try Task.checkCancellation()
                            return try await self.loadSearchResult(result, title: title, episode: episode)
                        } catch {
                            return []
                        }
                    }
                }
                while let result = await group.next() {
                    if !result.isEmpty {
                        group.cancelAll()
                        return result
                    }
                }
                return []
            }
            if !cues.isEmpty { return cues }
        }
        return []
    }

    private nonisolated static func automaticLoadCandidates(
        _ results: [DanmuSearchResult],
        title: String,
        episode: String
    ) -> [DanmuSearchResult] {
        DanmuCandidatePolicy.automaticLoadCandidates(results, title: title, episode: episode)
    }

    /// Providers run concurrently, but their configured priority determines
    /// which valid result wins. This avoids switching between different feeds
    /// for the same title based only on network response timing.
    private func firstNonEmpty<Input: Sendable, Output: Sendable>(
        from values: [Input],
        operation: @escaping (Input) async -> [Output]
    ) async -> [Output] {
        guard !values.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, [Output]).self) { group in
            for (index, value) in values.enumerated() {
                group.addTask {
                    (index, await operation(value))
                }
            }
            var completed = Array<[Output]?>(repeating: nil, count: values.count)
            var nextPriority = 0
            while let (index, result) = await group.next() {
                completed[index] = result
                while nextPriority < completed.count,
                      let prioritized = completed[nextPriority] {
                    if !prioritized.isEmpty {
                        group.cancelAll()
                        return prioritized
                    }
                    nextPriority += 1
                }
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                }
            }
            return []
        }
    }

    private func searchBuiltinResults(
        baseURL: String,
        query: String,
        episode: String
    ) async throws -> [DanmuSearchResult] {
        let cacheKey = builtinSearchCacheKey(baseURL: baseURL, query: query, episode: episode)
        if let cached = builtinSearchCache[cacheKey], Date().timeIntervalSince(cached.date) < Self.cacheLifetime {
            return cached.results
        }
        if let task = builtinSearchInFlight[cacheKey] {
            return try await task.value
        }
        let task = Task<[DanmuSearchResult], Error> { @MainActor [weak self] in
            guard let self else { return [] }
            return try await self.performBuiltinSearch(baseURL: baseURL, query: query, episode: episode)
        }
        builtinSearchInFlight[cacheKey] = task
        defer { builtinSearchInFlight[cacheKey] = nil }
        let results = try await task.value
        if !results.isEmpty {
            pruneCachesIfNeeded()
            builtinSearchCache[cacheKey] = (Date(), results)
        }
        return results
    }

    private func performBuiltinSearch(
        baseURL: String,
        query: String,
        episode: String
    ) async throws -> [DanmuSearchResult] {
        let episodeNumber = Self.extractEpisodeNumber(episode)
        var focusedResults: [DanmuSearchResult] = []
        if DanmuBuiltinSearchPolicy.shouldSearchFocusedEpisode(episodeNumber: episodeNumber) {
            focusedResults = await searchBuiltinEpisodes(
                baseURL: baseURL,
                query: query,
                episode: String(episodeNumber)
            )
        }
        if !DanmuBuiltinSearchPolicy.shouldRunFallbackSearch(
            episodeNumber: episodeNumber,
            focusedCandidateCount: focusedResults.count
        ) {
            return Self.prioritizeBuiltinResults(focusedResults, query: query, episode: episode)
        }

        var allResults = await searchBuiltinFallbackResults(baseURL: baseURL, query: query, episode: episode)

        if Self.automaticLoadCandidates(allResults, title: query, episode: episode).isEmpty,
           let variant = Self.searchTitleVariants(query).first {
            let animeURL = try Self.makeURL(
                baseURL: baseURL,
                path: "/api/v2/search/anime",
                queryItems: [URLQueryItem(name: "keyword", value: variant)]
            )
            do {
                let body = try await getDanmakuText(
                    from: animeURL.absoluteString,
                    timeout: Self.searchRequestTimeout
                )
                for animeID in Self.findAnimeIDs(in: body).prefix(5) {
                    try Task.checkCancellation()
                    guard let bangumiURL = try? Self.makeURL(
                        baseURL: baseURL,
                        path: "/api/v2/bangumi/\(Self.urlPathEscape(animeID))",
                        queryItems: []
                    ) else { continue }
                    guard let bangumi = try? await getDanmakuText(
                        from: bangumiURL.absoluteString,
                        timeout: Self.searchRequestTimeout
                    ) else { continue }
                    allResults.append(contentsOf: Self.parseBuiltinSearchResults(bangumi, baseURL: baseURL))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { return [] }
        }

        var seen = Set<String>()
        let uniqueResults = Self.automaticLoadCandidates(allResults, title: query, episode: episode)
            .filter { seen.insert($0.url).inserted }
        return Self.prioritizeBuiltinResults(uniqueResults, query: query, episode: episode)
    }

    private func searchBuiltinFallbackResults(
        baseURL: String,
        query: String,
        episode: String
    ) async -> [DanmuSearchResult] {
        // The focused episode query has already missed; try broader matches now.
        async let matchedTask = searchBuiltinMatches(baseURL: baseURL, title: query, episode: episode)
        async let broadTask = searchBuiltinEpisodes(baseURL: baseURL, query: query, episode: nil)
        let (matchedResults, broadResults) = await (matchedTask, broadTask)
        let allResults = matchedResults + broadResults
        var seen = Set<String>()
        let uniqueResults = Self.automaticLoadCandidates(allResults, title: query, episode: episode)
            .filter { seen.insert($0.url).inserted }
        return Self.prioritizeBuiltinResults(uniqueResults, query: query, episode: episode)
    }

    private func builtinSearchCacheKey(baseURL: String, query: String, episode: String) -> String {
        "\(baseURL.lowercased())\u{1E}\(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\u{1F}\(episode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func searchBuiltinEpisodes(
        baseURL: String,
        query: String,
        episode: String?
    ) async -> [DanmuSearchResult] {
        let titleVariants = Self.searchTitleVariants(query)
        return await withTaskGroup(of: [DanmuSearchResult].self) { group in
            for variant in titleVariants {
                group.addTask { [weak self] in
                    guard let self,
                          let episodesURL = try? Self.makeURL(
                            baseURL: baseURL,
                            path: "/api/v2/search/episodes",
                            queryItems: [
                                URLQueryItem(name: "anime", value: variant),
                                episode.map { URLQueryItem(name: "episode", value: $0) }
                            ].compactMap({ $0 })
                          ) else { return [] }
                    do {
                        let body = try await self.getDanmakuText(
                            from: episodesURL.absoluteString,
                            timeout: Self.searchRequestTimeout
                        )
                        return Self.parseBuiltinSearchResults(body, baseURL: baseURL)
                    } catch {
                        return []
                    }
                }
            }
            while let results = await group.next() {
                let validResults = Self.automaticLoadCandidates(
                    results,
                    title: query,
                    episode: episode ?? ""
                )
                if !validResults.isEmpty {
                    group.cancelAll()
                    return validResults
                }
            }
            return []
        }
    }

    private static func prioritizeBuiltinResults(
        _ results: [DanmuSearchResult],
        query: String,
        episode: String
    ) -> [DanmuSearchResult] {
        let episodeNumber = extractEpisodeNumber(episode)
        return results.enumerated().sorted { lhs, rhs in
            func score(_ result: DanmuSearchResult) -> Int {
                let name = result.name.lowercased()
                var value = 0
                if name.contains("电影") || name.contains("movie") || DanmuCandidatePolicy.isMovie(result.mediaType ?? "") { value += 30 }
                if name.contains("电视剧") || name.contains("tv") { value -= 10 }
                if DanmuCandidatePolicy.isPromotional(name) { value -= 100 }
                if episodeNumber > 0 {
                    value += DanmakuEpisodeMatcher.matches(
                        requestedEpisode: episode,
                        title: result.name
                    ) ? 100 : -20
                }
                let normalizedQuery = DanmakuCacheKey.normalizeTitle(query)
                if !normalizedQuery.isEmpty,
                   DanmakuCacheKey.normalizeTitle(result.name).contains(normalizedQuery) {
                    value += 5
                }
                return value
            }
            let leftScore = score(lhs.element)
            let rightScore = score(rhs.element)
            return leftScore == rightScore ? lhs.offset < rhs.offset : leftScore > rightScore
        }
        .map(\.element)
    }

    private static func parseSearchResults(_ body: String) -> [DanmuSearchResult] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            return [DanmuSearchResult(name: trimmed, url: trimmed, isBuiltin: false)]
        }
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let items = object as? [[String: Any]] {
            return parseCustomResultItems(items)
        }
        guard let dictionary = object as? [String: Any] else { return [] }
        for key in ["data", "list", "results"] {
            if let items = dictionary[key] as? [[String: Any]] {
                return parseCustomResultItems(items)
            }
        }
        let url = jsonString(dictionary["url"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return [] }
        let name = ["name", "title"].map { jsonString(dictionary[$0]) }.first { !$0.isEmpty } ?? url
        return [DanmuSearchResult(name: name, url: url, isBuiltin: false)]
    }

    private static func parseCustomResultItems(_ items: [[String: Any]]) -> [DanmuSearchResult] {
        items.compactMap { item in
            let url = jsonString(item["url"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let name = ["name", "title", "episode", "vod_name"]
                .map { jsonString(item[$0]) }
                .first { !$0.isEmpty } ?? url
            return DanmuSearchResult(
                name: name,
                url: url,
                isBuiltin: false,
                mediaType: jsonString(item["typeDescription"] ?? item["type"])
            )
        }
    }

    private nonisolated static func parseBuiltinSearchResults(_ body: String, baseURL: String) -> [DanmuSearchResult] {
        guard let object = jsonObject(body) else { return [] }
        var results: [DanmuSearchResult] = []
        func appendEpisodes(_ value: [String: Any], prefix: String = "", inheritedMediaType: String = "") {
            guard let episodes = value["episodes"] as? [[String: Any]] else { return }
            let valueMediaType = firstString(value, keys: ["typeDescription", "type"])
            let mediaType = valueMediaType.isEmpty ? inheritedMediaType : valueMediaType
            for episode in episodes {
                let id = firstString(episode, keys: ["episodeId", "id"])
                guard !id.isEmpty else { continue }
                let title = firstString(episode, keys: ["episodeTitle", "title", "name"])
                let label = [prefix, title].filter { !$0.isEmpty }.joined(separator: " ")
                let videoURL = firstString(episode, keys: ["url", "videoURL", "videoUrl"])
                let url = DanmuMatchRequestPolicy.commentURL(baseURL: baseURL, videoURL: videoURL)
                    ?? "\(baseURL)/api/v2/comment/\(urlPathEscape(id))?format=json"
                results.append(DanmuSearchResult(
                    name: label.isEmpty ? id : label,
                    url: url,
                    isBuiltin: true,
                    mediaType: mediaType
                ))
            }
        }

        appendEpisodes(object)
        if let bangumi = object["bangumi"] as? [String: Any] {
            appendEpisodes(
                bangumi,
                prefix: firstString(bangumi, keys: ["animeTitle", "title", "name"]),
                inheritedMediaType: firstString(bangumi, keys: ["typeDescription", "type"])
            )
        }
        if let data = object["data"] as? [String: Any] {
            appendEpisodes(data, prefix: firstString(data, keys: ["animeTitle", "title", "name"]))
            if let bangumi = data["bangumi"] as? [String: Any] {
                appendEpisodes(
                    bangumi,
                    prefix: firstString(bangumi, keys: ["animeTitle", "title", "name"]),
                    inheritedMediaType: firstString(data, keys: ["typeDescription", "type"])
                )
            }
        }
        for key in ["animes", "anime", "data"] {
            guard let items = object[key] as? [[String: Any]] else { continue }
            for item in items {
                let name = firstString(item, keys: ["animeTitle", "title", "name"])
                let mediaType = firstString(item, keys: ["typeDescription", "type"])
                appendEpisodes(item, prefix: name, inheritedMediaType: mediaType)
                if let bangumi = item["bangumi"] as? [String: Any] {
                    appendEpisodes(bangumi, prefix: name, inheritedMediaType: mediaType)
                }
            }
        }
        return results
    }

    /// Parses an already downloaded XML or comments/data JSON payload.
    public nonisolated static func parse(_ body: String) -> [DanmuCue] {
        DanmuCueParser.parse(body)
    }

    private func resolveAPIURLs(_ configuration: Configuration) -> [String] {
        let defaults = UserDefaults.standard
        let useDefault = configuration.useDefault
            ?? (defaults.object(forKey: Self.useDefaultKey) as? Bool)
            ?? false
        return DanmuAPISelectionPolicy.candidates(
            explicit: configuration.apiURL,
            useDefault: useDefault,
            saved: Self.firstDefaultValue(keys: [Self.customAPIKey, "danmaku_api", "danmaku"]),
            configured: ApiConfig.shared.danmaku,
            builtin: Self.builtinAPI,
            fallbacks: Self.builtinFallbackAPIs
        )
    }

    private func resolveAutomaticAPIURLs(_ configuration: Configuration) -> [String] {
        DanmuAPISelectionPolicy.automaticCandidates(
            explicit: configuration.apiURL,
            selected: resolveAPIURLs(configuration),
            builtin: Self.builtinAPI,
            fallbacks: Self.builtinFallbackAPIs
        )
    }

    private func loadBuiltin(
        baseURL: String,
        title: String,
        episode: String
    ) async throws -> [DanmuCue] {
        let candidates = try await searchBuiltinResults(
            baseURL: baseURL,
            query: title,
            episode: episode
        )
        let directCues = await loadFirstAvailable(
            candidates,
            title: title,
            episode: episode
        )
        if !directCues.isEmpty { return directCues }
        let episodeNumber = Self.extractEpisodeNumber(episode)
        if episodeNumber > 0, !candidates.isEmpty {
            let fallbackCandidates = await searchBuiltinFallbackResults(
                baseURL: baseURL,
                query: title,
                episode: episode
            )
            let seenURLs = Set(candidates.map(\.url))
            let uniqueFallbacks = fallbackCandidates.filter { !seenURLs.contains($0.url) }
            if !uniqueFallbacks.isEmpty {
                pruneCachesIfNeeded()
                builtinSearchCache[builtinSearchCacheKey(baseURL: baseURL, query: title, episode: episode)] = (
                    Date(),
                    candidates + uniqueFallbacks
                )
                let fallbackCues = await loadFirstAvailable(uniqueFallbacks, title: title, episode: episode)
                if !fallbackCues.isEmpty { return fallbackCues }
            }
        }
        guard !candidates.isEmpty else { return [] }

        // Some servers return only anime search results from the episodes route.
        let titleVariants = Self.searchTitleVariants(title)
        let animeURL = try Self.makeURL(
            baseURL: baseURL,
            path: "/api/v2/search/anime",
            queryItems: [URLQueryItem(name: "keyword", value: titleVariants.first ?? title)]
        )
        guard let animeBody = try? await getDanmakuText(
            from: animeURL.absoluteString,
            timeout: Self.searchRequestTimeout
        ) else {
            return []
        }

        let animeIDs = Self.findAnimeIDs(in: animeBody)
        for animeID in animeIDs {
            try Task.checkCancellation()
            guard let bangumiURL = try? Self.makeURL(
                baseURL: baseURL,
                path: "/api/v2/bangumi/\(Self.urlPathEscape(animeID))",
                queryItems: []
            ), let bangumiBody = try? await getDanmakuText(
                from: bangumiURL.absoluteString,
                timeout: Self.searchRequestTimeout
            ) else { continue }
            let bangumiResults = Self.parseBuiltinSearchResults(bangumiBody, baseURL: baseURL)
            let matchingResults = Self.automaticLoadCandidates(
                bangumiResults,
                title: title,
                episode: episode
            )
            let cues = await loadFirstAvailable(matchingResults, title: title, episode: episode)
            if !cues.isEmpty { return cues }
        }
        return []
    }

    private func searchBuiltinMatches(
        baseURL: String,
        title: String,
        episode: String
    ) async -> [DanmuSearchResult] {
        let fileName = DanmuMatchRequestPolicy.fileName(
            title: Self.searchTitleVariants(title).first ?? title,
            episode: episode
        )
        guard let matchURL = try? Self.makeURL(
            baseURL: baseURL,
            path: "/api/v2/match",
            queryItems: []
        ), let requestBody = DanmuMatchRequestPolicy.requestBody(fileName: fileName),
           let body = try? await getDanmakuText(
            from: matchURL.absoluteString,
            timeout: Self.searchRequestTimeout,
            method: "POST",
            body: requestBody,
            contentType: "application/json"
           ) else {
            return []
        }

        return DanmuMatchRequestPolicy.parseMatches(body).compactMap { match in
            guard let commentURL = DanmuMatchRequestPolicy.commentURL(
                baseURL: baseURL,
                videoURL: match.videoURL
            ) else { return nil }
            let name = match.displayTitle.isEmpty ? fileName : match.displayTitle
            return DanmuSearchResult(
                name: name,
                url: commentURL,
                isBuiltin: true,
                mediaType: match.mediaType
            )
        }
    }

    private func loadComments(baseURL: String, match: EpisodeMatch) async throws -> [DanmuCue] {
        if !match.videoURL.isEmpty,
           let commentURL = DanmuMatchRequestPolicy.commentURL(baseURL: baseURL, videoURL: match.videoURL) {
            do {
                let comments = try await getDanmakuText(
                    from: commentURL,
                    timeout: Self.commentRequestTimeout
                )
                let cues = try await Self.parseOffMain(comments)
                if !cues.isEmpty { return cues }
            } catch let error as NetworkError {
                if case .httpError(429) = error { throw error }
                // Continue with the comment-id route for older compatible servers.
            } catch {
                // Continue with the comment-id route for older compatible servers.
            }
        }

        // Some deployments reject the optional format query with 404 while
        // returning the same JSON from the canonical path. Keep both forms,
        // matching the Android client's tolerant behaviour.
        let paths = [
            ("/api/v2/comment/\(Self.urlPathEscape(match.id))", []),
            ("/api/v2/comment/\(Self.urlPathEscape(match.id))", [URLQueryItem(name: "format", value: "json")])
        ]
        for (path, queryItems) in paths {
            guard let commentURL = try? Self.makeURL(baseURL: baseURL, path: path, queryItems: queryItems),
                  !commentURL.absoluteString.isEmpty else { continue }
            let comments: String
            do {
                comments = try await getDanmakuText(
                    from: commentURL.absoluteString,
                    timeout: Self.commentRequestTimeout
                )
            } catch let error as NetworkError {
                if case .httpError(429) = error { throw error }
                continue
            } catch { continue }
            let cues = try await Self.parseOffMain(comments)
            if !cues.isEmpty { return cues }
            break
        }
        return []
    }

    private func getDanmakuText(
        from urlString: String,
        timeout: Int,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/x-www-form-urlencoded; charset=utf-8"
    ) async throws -> String {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NetworkError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = TimeInterval(max(3, timeout))
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        if body != nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        var lastError: Error?
        for attempt in 0...Self.requestRetryCount {
            do {
                try Task.checkCancellation()
                let (data, response) = try await customSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                guard (200...299).contains(http.statusCode) else {
                    if http.statusCode == 429, attempt < Self.requestRetryCount {
                        let delay = Self.retryAfterDelay(for: http)
                        if delay <= Self.retryMaxDelay {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        }
                    }
                    throw NetworkError.httpError(http.statusCode)
                }
                return Self.decodeText(data: data, response: http)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < Self.requestRetryCount, Self.shouldRetry(error) {
                    let exponential = min(
                        Self.retryBaseDelay * pow(2.0, Double(attempt)),
                        Self.retryMaxDelay
                    )
                    let jitter = Double.random(in: 0...0.2)
                    try await Task.sleep(nanoseconds: UInt64((exponential + jitter) * 1_000_000_000))
                }
            }
        }
        throw lastError ?? NetworkError.invalidResponse
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            if case .httpError(let status) = networkError {
                return [408, 425, 500, 502, 503, 504].contains(status)
            }
            return false
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorDataNotAllowed
        ].contains(nsError.code)
    }

    private static func retryAfterDelay(for response: HTTPURLResponse) -> TimeInterval {
        if let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let seconds = TimeInterval(value), seconds >= 0 {
                return seconds
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
            if let retryDate = formatter.date(from: value) {
                return max(0, retryDate.timeIntervalSinceNow)
            }
        }
        return min(Self.retryBaseDelay * 3, Self.retryMaxDelay)
    }

    private static func decodeText(data: Data, response: HTTPURLResponse) -> String {
        if let charset = response.textEncodingName,
           let encoding = encoding(fromIANACharset: charset),
           let value = String(data: data, encoding: encoding) {
            return value
        }
        for charset in ["utf-8", "gb18030", "gbk", "gb2312", "utf-16"] {
            if let encoding = encoding(fromIANACharset: charset),
               let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func encoding(fromIANACharset charset: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private func loadCustom(
        apiURL: String,
        title: String,
        episode: String,
        followURL: Bool = true
    ) async throws -> String {
        let name = Self.transliterateToSimplified(title)
        let episodeValue = Self.transliterateToSimplified(episode)
        if apiURL.contains("{name}") || apiURL.contains("{episode}") {
            let replaced = apiURL
                .replacingOccurrences(of: "{name}", with: Self.urlQueryEscape(name))
                .replacingOccurrences(of: "{episode}", with: Self.urlQueryEscape(episodeValue))
            return try await getDanmakuText(from: replaced, timeout: Self.searchRequestTimeout)
        }

        guard URL(string: apiURL) != nil else { throw NetworkError.invalidURL(apiURL) }
        let formBody = "name=\(Self.urlQueryEscape(name))&episode=\(Self.urlQueryEscape(episodeValue))"
        let body = try await getDanmakuText(
            from: apiURL,
            timeout: Self.searchRequestTimeout,
            method: "POST",
            body: formBody.data(using: .utf8)
        )
        if followURL, let nestedURL = Self.extractURL(from: body), nestedURL != apiURL {
            return try await getDanmakuText(from: nestedURL, timeout: Self.commentRequestTimeout)
        }
        return body
    }

    private static func parseOffMain(_ body: String) async throws -> [DanmuCue] {
        try Task.checkCancellation()
        return await Task.detached(priority: .utility) {
            DanmuCueParser.parse(body)
        }.value
    }

    private static let useDefaultKey = "danmu_api_use_default"
    private static let customAPIKey = "danmu_api"

    private static func firstDefaultValue(keys: [String]) -> String? {
        for key in keys {
            if let value = UserDefaults.standard.string(forKey: key)?.trimmedNonEmpty {
                return value
            }
        }
        return nil
    }

    private static func isBuiltinAPI(_ value: String) -> Bool {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasSuffix("/") { normalized.removeLast() }
        let known = ([builtinAPI] + builtinFallbackAPIs).map {
            var value = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while value.hasSuffix("/") { value.removeLast() }
            return value
        }
        return known.contains(normalized)
            || normalized.hasSuffix("/87654321")
    }

    private static func normalizeBaseURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") { result.removeLast() }
        if result.hasSuffix("/87654321") {
            result.removeLast("/87654321".count)
        }
        return result
    }

    private static func builtinCommentURLs(for value: String) -> [String] {
        guard let original = URLComponents(string: value) else { return [value] }
        let originalPath = original.path
        guard let routeRange = originalPath.range(of: "/api/v2/comment") else {
            return [value]
        }
        let route = String(originalPath[routeRange.lowerBound...])
        var candidates = [value]
        for api in [builtinAPI] + builtinFallbackAPIs {
            guard let base = URLComponents(string: normalizeBaseURL(api)) else { continue }
            var components = base
            let basePath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let routePath = route.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + ([basePath, routePath].filter { !$0.isEmpty }.joined(separator: "/"))
            components.queryItems = original.queryItems
            guard let formattedURL = components.url?.absoluteString else { continue }
            candidates.append(formattedURL)

            var withoutFormat = components
            let queryItems = withoutFormat.queryItems?.filter { $0.name != "format" } ?? []
            if queryItems.count != (withoutFormat.queryItems?.count ?? 0) {
                withoutFormat.queryItems = queryItems.isEmpty ? nil : queryItems
                if let fallbackURL = withoutFormat.url?.absoluteString {
                    candidates.append(fallbackURL)
                }
            }
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }

    private nonisolated static func makeURL(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        guard let base = URL(string: baseURL), var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL)
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathPart = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, pathPart].filter { !$0.isEmpty }.joined(separator: "/"))
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw NetworkError.invalidURL(baseURL) }
        return url
    }

    private nonisolated static func urlPathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func urlQueryEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func transliterateToSimplified(_ value: String) -> String {
        // The Android client normalizes through Trans.t2s. Foundation has no
        // built-in Traditional-to-Simplified converter, so preserve the input.
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// XGZY episode names often contain source/quality suffixes that are not
    /// part of the title indexed by the danmaku service. Search both the raw
    /// title and a conservative cleaned form before falling back to anime API.
    private static func searchTitleVariants(_ value: String) -> [String] {
        let raw = transliterateToSimplified(value)
        var cleaned = raw
        let patterns = [
            #"\[[^\]]*\]"#,
            #"【[^】]*】"#,
            #"\([^\)]*\)"#,
            #"（[^）]*）"#
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        cleaned = cleaned
            .replacingOccurrences(of: "HD中字", with: "")
            .replacingOccurrences(of: "HD国语", with: "")
            .replacingOccurrences(of: "HD粤语", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        for item in [raw, cleaned] where !item.isEmpty && !result.contains(item) {
            result.append(item)
        }
        return result.isEmpty ? [raw] : result
    }

    private struct EpisodeMatch {
        let id: String
        let title: String
        let videoURL: String
    }

    private nonisolated static func findAnimeIDs(in body: String) -> [String] {
        guard let object = jsonObject(body) else { return [] }
        let arrays = ["animes", "anime", "data"]
        var ids: [String] = []
        for key in arrays {
            if let items = object[key] as? [[String: Any]] {
                ids.append(contentsOf: items.map { firstString($0, keys: ["animeId", "id"]) })
            }
        }
        if ids.isEmpty {
            let id = firstString(object, keys: ["animeId", "id"])
            if !id.isEmpty { ids.append(id) }
        }
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private nonisolated static func findEpisodes(in body: String, requestedEpisode: String) -> [EpisodeMatch] {
        guard let object = jsonObject(body) else { return [] }
        let episodeArrays = episodeArrays(in: object)
        var matches: [EpisodeMatch] = []

        for item in episodeArrays {
            let id = firstString(item, keys: ["episodeId", "id"])
            guard !id.isEmpty else { continue }
            let title = firstString(item, keys: ["episodeTitle", "title", "name"])
            let rawNumber = firstString(item, keys: ["episodeNumber", "number", "sort"])
            let number = parseEpisodeNumber(rawNumber)
            let match = EpisodeMatch(
                id: id,
                title: title,
                videoURL: firstString(item, keys: ["url", "videoURL", "videoUrl"])
            )
            if DanmakuEpisodeMatcher.matches(
                requestedEpisode: requestedEpisode,
                title: title,
                explicitNumber: number
            ) {
                matches.append(match)
            }
        }

        if matches.isEmpty {
            // Movies are represented by the same `episodes` array, but their
            // names are usually "国语/粤语/中字" rather than "第1集". The
            // Android client deliberately falls back to the first movie
            // episode (preferring the requested language) in this case.
            if isMovieResult(object) {
                let preferCantonese = requestedEpisode.localizedCaseInsensitiveContains("粤")
                let movieMatches = episodeArrays.compactMap { item -> EpisodeMatch? in
                    let id = firstString(item, keys: ["episodeId", "id"])
                    guard !id.isEmpty else { return nil }
                    return EpisodeMatch(
                        id: id,
                        title: firstString(item, keys: ["episodeTitle", "title", "name"]),
                        videoURL: firstString(item, keys: ["url", "videoURL", "videoUrl"])
                    )
                }
                if let preferred = movieMatches.first(where: {
                    preferCantonese
                        ? $0.title.localizedCaseInsensitiveContains("粤")
                        : ($0.title.localizedCaseInsensitiveContains("国")
                            || $0.title.localizedCaseInsensitiveContains("普通话"))
                }) {
                    return [preferred]
                }
                if let first = movieMatches.first { return [first] }
            }
            if requestedEpisode.isEmpty {
                return episodeArrays.compactMap { item in
                    let id = firstString(item, keys: ["episodeId", "id"])
                    guard !id.isEmpty else { return nil }
                    return EpisodeMatch(
                        id: id,
                        title: firstString(item, keys: ["episodeTitle", "title", "name"]),
                        videoURL: firstString(item, keys: ["url", "videoURL", "videoUrl"])
                    )
                }
            }
        }
        return matches
    }

    private nonisolated static func isMovieResult(_ object: [String: Any]) -> Bool {
        func isMovie(_ value: String) -> Bool {
            value.localizedCaseInsensitiveContains("电影")
                || value.localizedCaseInsensitiveContains("movie")
        }
        if isMovie(firstString(object, keys: ["type", "typeDescription"])) { return true }
        if let bangumi = object["bangumi"] as? [String: Any],
           isMovie(firstString(bangumi, keys: ["type", "typeDescription"])) {
            return true
        }
        for key in ["animes", "anime", "data"] {
            guard let items = object[key] as? [[String: Any]] else { continue }
            if items.contains(where: {
                isMovie(firstString($0, keys: ["type", "typeDescription"]))
            }) {
                return true
            }
        }
        return false
    }

    private nonisolated static func episodeArrays(in object: [String: Any]) -> [[String: Any]] {
        if let episodes = object["episodes"] as? [[String: Any]] { return episodes }
        if let bangumi = object["bangumi"] as? [String: Any],
           let episodes = bangumi["episodes"] as? [[String: Any]] {
            return episodes
        }

        var nestedEpisodes: [[String: Any]] = []
        for key in ["animes", "anime", "data"] {
            guard let items = object[key] as? [[String: Any]] else { continue }
            for item in items {
                if let episodes = item["episodes"] as? [[String: Any]] {
                    nestedEpisodes.append(contentsOf: episodes)
                }
            }
        }
        return nestedEpisodes
    }

    private nonisolated static func parseEpisodeNumber(_ value: String) -> Int {
        if let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int(number)
        }
        return extractNumber(from: value)
    }

    private nonisolated static func extractNumber(from value: String) -> Int {
        extractEpisodeNumber(value)
    }

    /// Mirrors Android DanmuEpisodeMatcher.episodeNumber(): prefer the
    /// episode portion of SxxExx/EPx labels instead of concatenating season
    /// and episode digits (S01E02 must resolve to episode 2, not 102).
    private nonisolated static func extractEpisodeNumber(_ value: String) -> Int {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)S\s*\d+\s*E\s*0*(\d+)"#,
            #"(?i)(?:EP|第)\s*0*(\d+)"#,
            #"(?i)(?:^|[^A-Za-z])0*(\d+)\s*(?:集|话|期|回)?$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized),
                  let number = Int(normalized[range]) else { continue }
            return number
        }
        guard let regex = try? NSRegularExpression(pattern: #"\d+"#),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let range = Range(match.range, in: normalized) else { return -1 }
        return Int(normalized[range]) ?? -1
    }

    private nonisolated static func jsonObject(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func jsonString(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private nonisolated static func firstString(_ object: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }

    private static func extractURL(from body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            return trimmed
        }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = object["url"] as? String,
           !url.isEmpty {
            return url
        }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let url = array.lazy.compactMap({ $0["url"] as? String }).first(where: { !$0.isEmpty }) {
            return url
        }
        return nil
    }
}

private enum DanmuCueParser {
    static func parse(_ body: String) -> [DanmuCue] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.first == "<" {
            let xmlCues = parseXML(trimmed)
            if !xmlCues.isEmpty { return xmlCues }
        }
        if let jsonCues = parseJSON(trimmed), !jsonCues.isEmpty {
            return jsonCues
        }
        return parseXMLWithRegex(trimmed)
    }

    private static func parseXML(_ body: String) -> [DanmuCue] {
        guard let data = body.data(using: .utf8) else { return [] }
        let delegate = XMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return normalized(delegate.cues)
    }

    private static func parseJSON(_ body: String) -> [DanmuCue]? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let items: [[String: Any]]
        if let array = object as? [[String: Any]] {
            items = array
        } else if let dictionary = object as? [String: Any] {
            items = ["comments", "data", "danmaku"].compactMap { dictionary[$0] as? [[String: Any]] }.flatMap { $0 }
        } else {
            return []
        }

        let cues = items.compactMap { item -> DanmuCue? in
            let param = scalarString(item["p"])
            var text = scalarString(item["m"])
            if text.isEmpty { text = scalarString(item["text"]) }
            guard !param.isEmpty, !text.isEmpty else { return nil }
            // The builtin API uses `time,type,color,source` while the
            // Android parser expects `time,type,size,color`.
            return makeCue(param: normalizeDanmakuParam(param), text: text)
        }
        return normalized(cues)
    }

    private static func parseXMLWithRegex(_ body: String) -> [DanmuCue] {
        let pattern = #"(?is)<d\b[^>]*\bp\s*=\s*([\"'])(.*?)\1[^>]*>(.*?)</d\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let cues = regex.matches(in: body, range: range).compactMap { match -> DanmuCue? in
            guard let paramRange = Range(match.range(at: 2), in: body),
                  let textRange = Range(match.range(at: 3), in: body) else { return nil }
            return makeCue(
                param: String(body[paramRange]),
                text: decodeXML(String(body[textRange]))
            )
        }
        return normalized(cues)
    }

    private static func makeCue(param: String, text: String) -> DanmuCue? {
        let values = param.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let time = Double(values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              time.isFinite else { return nil }
        let type = Int(values[safe: 1] ?? "1") ?? 1
        var size = Double(values[safe: 2] ?? "25") ?? 25
        var color = parseColor(values[safe: 3]) ?? 0xFFFFFF

        // The Android compatibility path accepts feeds that put the color in
        // the third slot and omit a valid fourth-slot color.
        if let third = parseColor(values[safe: 2]), parseColor(values[safe: 3]) == nil {
            color = third
            size = 25
        }
        guard !text.isEmpty else { return nil }
        return DanmuCue(
            time: max(0, time),
            type: type,
            size: size > 0 && size.isFinite ? size : 25,
            color: color,
            text: decodeXML(text)
        )
    }

    private static func normalizeDanmakuParam(_ param: String) -> String {
        let values = param.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard values.count >= 4 else { return param }
        let time = values[0]
        let type = values[1]
        let size = values[2]
        let color = values[3]
        if parseColor(color) == nil {
            // A color-only feed normally contains a 24-bit numeric value in
            // the third slot and a source label in the fourth slot. Small
            // values (for example the normal font size 25) remain sizes.
            let looksLikeColorOnly = size.hasPrefix("#")
                || size.lowercased().hasPrefix("0x")
                || (Int(size).map { $0 > 255 } ?? false)
            if looksLikeColorOnly, parseColor(size) != nil {
                return "\(time),\(type),25,\(normalizeColorValue(size))"
            }
            return "\(time),\(type),\(size),16777215"
        }
        return "\(time),\(type),\(size),\(normalizeColorValue(color))"
    }

    private static func normalizeColorValue(_ value: String) -> String {
        guard let color = parseColor(value) else { return "16777215" }
        return String(color)
    }

    private static func parseColor(_ value: String?) -> Int? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("#") {
            return Int(text.dropFirst(), radix: 16).map { $0 & 0xFFFFFF }
        }
        if text.lowercased().hasPrefix("0x") {
            return Int(text.dropFirst(2), radix: 16).map { $0 & 0xFFFFFF }
        }
        guard let value = Int(text), (0...0xFFFFFF).contains(value) else { return nil }
        return value
    }

    private static func scalarString(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func normalized(_ cues: [DanmuCue]) -> [DanmuCue] {
        cues.sorted {
            if $0.time == $1.time { return $0.id < $1.id }
            return $0.time < $1.time
        }
    }

    private static func decodeXML(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        let pattern = #"&#(x[0-9a-fA-F]+|[0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let token = String(result[valueRange])
            let scalar: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalar = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalar = UInt32(token)
            }
            if let scalar, let unicode = UnicodeScalar(scalar) {
                result.replaceSubrange(range, with: String(unicode))
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class XMLDelegate: NSObject, XMLParserDelegate {
        var cues: [DanmuCue] = []
        private var currentParam: String?
        private var currentText = ""

        func parser(
            _: XMLParser,
            didStartElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName.caseInsensitiveCompare("d") == .orderedSame else { return }
            currentParam = attributeDict["p"] ?? attributeDict["P"]
            currentText = ""
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            guard currentParam != nil else { return }
            currentText += string
        }

        func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
            guard currentParam != nil else { return }
            currentText += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _: XMLParser,
            didEndElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?
        ) {
            guard elementName.caseInsensitiveCompare("d") == .orderedSame,
                  let currentParam,
                  let cue = makeCue(param: currentParam, text: currentText) else { return }
            cues.append(cue)
            self.currentParam = nil
            currentText = ""
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
