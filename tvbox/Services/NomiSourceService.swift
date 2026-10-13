import Foundation

enum NomiSourceService {
    private static let defaultOrigin = URL(string: "https://vip.wwgz.cn:5200")!
    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
    private static let anchorPattern = try! NSRegularExpression(
        pattern: #"(?is)<a\b([^>]*)>(.*?)</a\s*>"#
    )

    private struct Anchor {
        let attributes: String
        let body: String
    }

    struct EpisodeList {
        let name: String
        let entries: [String]
    }

    static let categories: [(id: String, name: String)] = [
        ("1", "电影"), ("2", "电视剧"), ("3", "综艺"), ("4", "动漫"), ("26", "短剧")
    ]

    static func search(source: SourceBean, keyword: String) async throws -> [Movie.Video] {
        let origin = origin(for: source)
        var components = URLComponents(url: origin.appendingPathComponent("index.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "m", value: "vod-search"),
            URLQueryItem(name: "wd", value: keyword)
        ]
        guard let url = components?.url else { throw SourceError.invalidApiUrl(source.api) }
        let html = try await fetch(url, source: source, referer: origin.absoluteString)
        return parseSearchResults(html, sourceKey: source.key, baseURL: origin)
    }

    static func category(source: SourceBean, id: String, page: Int) async throws -> [Movie.Video] {
        let origin = origin(for: source)
        let categoryID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let path = "/index.php?m=vod-list-id-\(categoryID)-pg-\(max(1, page))-order--by--class--year--letter--area--lang-.html"
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw SourceError.invalidApiUrl(source.api)
        }
        let html = try await fetch(url, source: source, referer: origin.absoluteString)
        return parseSearchResults(html, sourceKey: source.key, baseURL: origin)
    }

    static func detail(source: SourceBean, vodID: String) async throws -> VodInfo {
        let origin = origin(for: source)
        guard let detailURL = URL(string: vodID, relativeTo: origin)?.absoluteURL,
              detailURL.host?.caseInsensitiveCompare(origin.host ?? "") == .orderedSame else {
            throw SourceError.invalidPlayableURL(vodID)
        }
        let html = try await fetch(detailURL, source: source, referer: origin.absoluteString)
        let current = Movie.Video(id: detailURL.absoluteString, name: videoTitle(in: html))
        var video = current
        video.sourceKey = source.key
        video.pic = poster(in: html, baseURL: origin)
        video.note = firstNonEmpty(classText("sDes", in: html), classText("pBottom", in: html))
        video.year = firstMatch(#"(?:19|20)\d{2}"#, in: html) ?? ""

        let playlists = parseEpisodeLists(html, baseURL: origin)
        guard !playlists.isEmpty else { throw SourceError.invalidResponse("糯米详情页没有可播放剧集") }
        return VodInfo.from(
            video: video,
            playFrom: playlists.map(\.name).joined(separator: "$$$"),
            playUrl: playlists.map { $0.entries.joined(separator: "#") }.joined(separator: "$$$")
        )
    }

    static func resolvePlayableURL(source: SourceBean, episodeURL: String) async throws -> String {
        if let directURL = KktvsResponseNormalizer.directMediaURL(episodeURL) {
            return directURL
        }
        if episodeURL.range(of: #"(?i)^NBY-[A-Za-z0-9_+./=-]+(?:\|[A-Za-z0-9_+./=-]+)?$"#, options: .regularExpression) != nil {
            return try await resolveNby(episodeURL)
        }

        let origin = origin(for: source)
        guard let pageURL = URL(string: episodeURL, relativeTo: origin)?.absoluteURL,
              pageURL.host?.caseInsensitiveCompare(origin.host ?? "") == .orderedSame else {
            throw SourceError.invalidPlayableURL(episodeURL)
        }
        let html = try await fetch(pageURL, source: source, referer: pageURL.absoluteString)
        guard let selected = selectedEpisodeMediaURL(in: html, episodeURL: pageURL.absoluteString) else {
            throw SourceError.invalidResponse("糯米播放页没有返回当前集媒体地址")
        }
        if selected.range(of: #"(?i)^NBY-[A-Za-z0-9_+./=-]+(?:\|[A-Za-z0-9_+./=-]+)?$"#, options: .regularExpression) != nil {
            return try await resolveNby(selected)
        }
        guard let mediaURL = KktvsResponseNormalizer.directMediaURL(selected) else {
            throw SourceError.invalidPlayableURL(selected)
        }
        return mediaURL
    }

    static func parseSearchResults(_ html: String, sourceKey: String, baseURL: URL) -> [Movie.Video] {
        let listItems = captures(#"(?is)<li\b[^>]*>(.*?)</li\s*>"#, in: html)
        let blocks = listItems.isEmpty ? [html] : listItems
        var seen = Set<String>()
        var videos: [Movie.Video] = []

        for block in blocks {
            for anchor in anchors(in: block) {
                guard let href = attribute("href", in: anchor.attributes),
                      href.localizedCaseInsensitiveContains("vod-detail"),
                      let detailURL = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                      detailURL.host?.caseInsensitiveCompare(baseURL.host ?? "") == .orderedSame,
                      seen.insert(detailURL.absoluteString).inserted else { continue }

                let imageTag = capture(#"(?is)<img\b[^>]*>"#, in: block, group: 0) ?? ""
                let name = firstNonEmpty(
                    classText("sTit", in: block),
                    attribute("title", in: anchor.attributes),
                    attribute("alt", in: imageTag),
                    attribute("title", in: imageTag),
                    htmlText(anchor.body)
                )
                guard !name.isEmpty, !isActionText(name) else { continue }

                var video = Movie.Video(id: detailURL.absoluteString, name: name)
                video.sourceKey = sourceKey
                video.pic = posterURL(from: imageTag, baseURL: baseURL)
                video.note = firstNonEmpty(classText("sDes", in: block), classText("pBottom", in: block))
                video.year = firstMatch(#"(?:19|20)\d{2}"#, in: block) ?? ""
                videos.append(video)
                if videos.count >= 40 { return videos }
            }
        }
        return videos
    }

    static func parseEpisodeLists(_ html: String, baseURL: URL) -> [EpisodeList] {
        let routeNames = routeLabels(in: html)
        let listMatches = matches(
            #"(?is)<div\b([^>]*class=["'][^"']*\bnumList\b[^"']*["'][^>]*)>(.*?)</div\s*>"#,
            in: html
        )
        var lists: [EpisodeList] = []

        for (index, match) in listMatches.enumerated() {
            guard match.numberOfRanges > 2,
                  let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else { continue }
            let attributes = String(html[attributesRange])
            let body = String(html[bodyRange])
            let episodes = episodeEntries(from: body, baseURL: baseURL)
            guard !episodes.isEmpty else { continue }
            let name = firstNonEmpty(
                routeNames.indices.contains(index) ? routeNames[index] : nil,
                attribute("title", in: attributes),
                "糯米线路\(index + 1)"
            )
            lists.append(EpisodeList(name: name, entries: Array(episodes.reversed())))
        }

        if lists.isEmpty {
            let episodes = episodeEntries(from: html, baseURL: baseURL)
            if !episodes.isEmpty {
                lists.append(EpisodeList(name: "糯米线路", entries: Array(episodes.reversed())))
            }
        }
        return lists
    }

    static func selectedEpisodeMediaURL(in html: String, episodeURL: String) -> String? {
        guard let episodeNumber = capture(#"(?i)num-(\d+)"#, in: episodeURL),
              let index = Int(episodeNumber), index > 0,
              let rawPlaylist = capture(#"(?is)\bmac_url\s*=\s*['\"](.*?)['\"]"#, in: html),
              !rawPlaylist.isEmpty else { return nil }
        let playlist = unescapeJavaScript(rawPlaylist)
        let entries = playlist.split(separator: "#", omittingEmptySubsequences: true)
        guard entries.indices.contains(index - 1) else { return nil }
        let entry = String(entries[index - 1])
        guard let delimiter = entry.firstIndex(of: "$") else { return nil }
        let value = String(entry[entry.index(after: delimiter)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func resolveNby(_ value: String) async throws -> String {
        var components = URLComponents(string: "https://api.nbyjson.top:7788/api/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: "tviKuMb3MlqCW1I6gE"),
            URLQueryItem(name: "url", value: value)
        ]
        guard let url = components.url else { throw SourceError.invalidApiUrl(value) }
        let response = try await NetworkManager.shared.getString(
            from: url.absoluteString,
            headers: ["User-Agent": "okhttp-okgo/jeasonlzy"],
            timeout: 15,
            maxRetries: 1
        )
        guard let data = response.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mediaURL = (root["url"] as? String) ?? (root["m3u8"] as? String),
              KktvsResponseNormalizer.directMediaURL(mediaURL) != nil else {
            throw SourceError.invalidResponse("糯米 NBY 解析没有返回媒体地址")
        }
        return KktvsResponseNormalizer.normalizeMediaURL(mediaURL)
    }

    private static func episodeEntries(from html: String, baseURL: URL) -> [String] {
        anchors(in: html).compactMap { anchor in
            guard let href = attribute("href", in: anchor.attributes),
                  href.localizedCaseInsensitiveContains("vod-play"),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  url.host?.caseInsensitiveCompare(baseURL.host ?? "") == .orderedSame else { return nil }
            let number = capture(#"(?i)num-(\d+)"#, in: url.path) ?? ""
            let name = firstNonEmpty(
                htmlText(anchor.body),
                number.isEmpty ? nil : "第\(number)集",
                attribute("title", in: anchor.attributes).map(cleanEpisodeTitle)
            )
            guard !name.isEmpty else { return nil }
            return "\(name)$\(url.absoluteString)"
        }
    }

    private static func routeLabels(in html: String) -> [String] {
        guard let header = capture(
            #"(?is)<div\b[^>]*class=["'][^"']*\bhd\b[^"']*["'][^>]*>\s*<ul\b[^>]*>(.*?)</ul\s*>"#,
            in: html
        ) else { return [] }
        return captures(#"(?is)<li\b[^>]*>(.*?)</li\s*>"#, in: header)
            .map(htmlText)
            .filter { !$0.isEmpty }
    }

    private static func videoTitle(in html: String) -> String {
        let pageTitle = capture(#"(?is)<title\b[^>]*>(.*?)</title\s*>"#, in: html)
            .map(htmlText)?
            .replacingOccurrences(of: #"[|｜-].*$"#, with: "", options: .regularExpression)
        return firstNonEmpty(
            classText("sTit", in: html),
            capture(#"(?is)<h1\b[^>]*>(.*?)</h1\s*>"#, in: html).map(htmlText),
            pageTitle
        )
    }

    private static func poster(in html: String, baseURL: URL) -> String {
        posterURL(from: capture(#"(?is)<img\b[^>]*>"#, in: html, group: 0) ?? "", baseURL: baseURL)
    }

    private static func posterURL(from imageTag: String, baseURL: URL) -> String {
        let value = firstNonEmpty(
            attribute("data-original", in: imageTag),
            attribute("data-src", in: imageTag),
            attribute("src", in: imageTag)
        )
        return URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString ?? ""
    }

    private static func classText(_ className: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: className)
        return capture(
            "(?is)<[^>]+class=[\"'][^\"']*\\b\(escaped)\\b[^\"']*[\"'][^>]*>(.*?)</[^>]+>",
            in: html
        ).map(htmlText)
    }

    private static func anchors(in html: String) -> [Anchor] {
        anchorPattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else { return nil }
            return Anchor(attributes: String(html[attributesRange]), body: String(html[bodyRange]))
        }
    }

    private static func attribute(_ name: String, in value: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"(?is)\b\#(escaped)\s*=\s*"([^"]*)""#,
            #"(?is)\b\#(escaped)\s*=\s*'([^']*)'"#
        ]
        for pattern in patterns {
            if let result = capture(pattern, in: value) { return decodeEntities(result) }
        }
        return nil
    }

    private static func htmlText(_ html: String) -> String {
        let withoutCode = html.replacingOccurrences(
            of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        let withoutTags = withoutCode.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func cleanEpisodeTitle(_ value: String) -> String {
        htmlText(value)
            .replacingOccurrences(of: "在线播放", with: "")
            .replacingOccurrences(of: "第第", with: "第")
            .replacingOccurrences(of: "集集", with: "集")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isActionText(_ value: String) -> Bool {
        ["立即播放", "播放", "详情", "查看详情", "在线观看"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func unescapeJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression)
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func origin(for source: SourceBean) -> URL {
        guard let configured = URL(string: source.api),
              ["http", "https"].contains(configured.scheme?.lowercased() ?? ""),
              configured.host != nil else { return defaultOrigin }
        return configured
    }

    private static func fetch(_ url: URL, source: SourceBean, referer: String) async throws -> String {
        try await NetworkManager.shared.getString(
            from: url.absoluteString,
            headers: requestHeaders(source: source, referer: referer),
            timeout: 15,
            maxRetries: 1
        )
    }

    static func requestHeaders(source: SourceBean, referer: String) -> [String: String] {
        var headers = source.headers ?? [:]
        setHeader("User-Agent", value: mobileUserAgent, in: &headers)
        setHeader("Referer", value: referer, in: &headers)
        setHeader("Accept", value: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", in: &headers)
        return headers
    }

    private static func setHeader(_ name: String, value: String, in headers: inout [String: String]) {
        headers.keys.filter { $0.caseInsensitiveCompare(name) == .orderedSame }
            .forEach { headers.removeValue(forKey: $0) }
        headers[name] = value
    }

    private static func matches(_ pattern: String, in value: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
    }

    private static func captures(_ pattern: String, in value: String) -> [String] {
        matches(pattern, in: value).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func capture(_ pattern: String, in value: String, group: Int = 1) -> String? {
        guard let match = matches(pattern, in: value).first,
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: value) else { return nil }
        return String(value[range])
    }

    private static func firstMatch(_ pattern: String, in value: String) -> String? {
        capture(pattern, in: value, group: 0)
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0 }.first {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? ""
    }
}
