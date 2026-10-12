import Foundation
#if os(iOS)
import UIKit
import WebKit
#endif

enum Cz4kSourceService {
    private static let origin = "https://www.cz4k.com"
    private static let headers = PlaybackRequestHeaderPolicy.applyingSourceSpecificPlaybackHeaders(
        to: [:],
        sourceKey: "cz4k"
    )

    static func resolvePlaybackMedia(
        from rawURL: String,
        configuredHeaders: [String: String]? = nil
    ) async throws -> ResolvedPlaybackMedia? {
        #if os(iOS)
        guard let pageURL = URL(string: rawURL),
              let host = pageURL.host?.lowercased(),
              host == "cz4k.com" || host.hasSuffix(".cz4k.com"),
              KktvsResponseNormalizer.directMediaURL(rawURL) == nil else {
            return nil
        }

        var currentURL = pageURL
        var visited = Set<String>()
        var pageReferer: String?
        for hop in 0..<4 {
            guard visited.insert(currentURL.absoluteString).inserted else { break }
            let page = try await Cz4kBrowserSession.loadPage(
                currentURL,
                headers: isCz4kHost(currentURL.host) ? (configuredHeaders ?? [:]) : [:],
                referer: pageReferer,
                waitForMedia: true
            )
            if page.isHLSPlaylist {
                let requestHeaders = playbackHeaders(
                    for: currentURL.absoluteString,
                    referer: currentURL.absoluteString,
                    configuredHeaders: configuredHeaders,
                    cookie: page.cookieHeader(for: currentURL.absoluteString)
                )
                return ResolvedPlaybackMedia(url: currentURL.absoluteString, headers: requestHeaders)
            }
            let candidates = page.mediaURLs + [
                KktvsResponseNormalizer.extractMediaURL(
                    from: page.html,
                    baseURL: currentURL.absoluteString
                )
            ].compactMap { $0 }
            let directCandidates = candidates
                .filter { KktvsResponseNormalizer.directMediaURL($0) != nil }
                .sorted { mediaCandidatePriority($0) < mediaCandidatePriority($1) }
            let extracted = directCandidates.first ?? candidates.first
            guard let extracted,
                  let mediaURL = SourceService.validPlayableURL(extracted),
                  let mediaComponents = URLComponents(string: mediaURL),
                  ["http", "https"].contains(mediaComponents.scheme?.lowercased() ?? "") else {
                throw SourceError.invalidPlayableURL(currentURL.absoluteString)
            }

            if KktvsResponseNormalizer.directMediaURL(mediaURL) != nil {
                let requestHeaders = playbackHeaders(
                    for: mediaURL,
                    referer: currentURL.absoluteString,
                    configuredHeaders: configuredHeaders,
                    cookie: page.cookieHeader(for: mediaURL)
                )
                return ResolvedPlaybackMedia(url: mediaURL, headers: requestHeaders)
            }

            guard mediaURL != currentURL.absoluteString,
                  hop < 3,
                  let nextURL = URL(string: mediaURL) else { break }
            pageReferer = currentURL.absoluteString
            currentURL = nextURL
        }
        throw SourceError.invalidPlayableURL(rawURL)
        #else
        return nil
        #endif
    }

    private static func isCz4kHost(_ value: String?) -> Bool {
        guard let host = value?.lowercased() else { return false }
        return host == "cz4k.com" || host.hasSuffix(".cz4k.com")
    }

    private static func playbackHeaders(
        for mediaURL: String,
        referer: String,
        configuredHeaders: [String: String]?,
        cookie: String?
    ) -> [String: String] {
        var result = headers
        if let mediaHost = URLComponents(string: mediaURL)?.host, isCz4kHost(mediaHost) {
            configuredHeaders?.forEach { key, value in
                result.keys
                    .filter { $0.caseInsensitiveCompare(key) == .orderedSame }
                    .forEach { result.removeValue(forKey: $0) }
                result[key] = value
            }
        }
        result = PlaybackRequestHeaderPolicy.applyingRefererOverride(referer, to: result)
        if let cookie, !cookie.isEmpty {
            result.keys
                .filter { $0.caseInsensitiveCompare("Cookie") == .orderedSame }
                .forEach { result.removeValue(forKey: $0) }
            result["Cookie"] = cookie
        }
        return result
    }

    private static func mediaCandidatePriority(_ value: String) -> Int {
        let normalized = KktvsResponseNormalizer.normalizeMediaURL(value).lowercased()
        if normalized.contains(".m3u8") || normalized.contains(".m3u?") { return 0 }
        if normalized.contains(".mpd") { return 1 }
        if normalized.contains(".mp4") || normalized.contains(".m4v") { return 2 }
        if normalized.contains(".flv") || normalized.contains(".mkv") { return 3 }
        if normalized.contains(".ts") || normalized.contains(".m4s") { return 5 }
        return 4
    }
    static func search(keyword: String) async throws -> [Movie.Video] {
        var components = URLComponents(string: origin + "/nimasile")
        components?.queryItems = [URLQueryItem(name: "q", value: keyword)]
        guard let url = components?.url else { throw SourceError.invalidApiUrl(origin + "/nimasile") }
        let html = try await fetch(url.absoluteString)
        return Cz4kSearchParser.parse(html: html, baseURL: url)
    }

    static func detail(vodID: String) async throws -> VodInfo {
        guard let url = resolvedURL(vodID, relativeTo: URL(string: origin)!) else {
            throw SourceError.invalidPlayableURL(vodID)
        }
        let html = try await fetch(url.absoluteString)
        let title = firstNonEmpty(
            firstCapture(#"(?is)<h1\b[^>]*>(.*?)</h1>"#, in: html, group: 1).map(text),
            firstCapture(#"(?is)<meta\s+[^>]*property=[\"']og:title[\"'][^>]*content=[\"']([^\"']*)[\"'][^>]*>"#, in: html, group: 1),
            firstCapture(#"(?is)<title\b[^>]*>(.*?)</title>"#, in: html, group: 1).map(text)
        )
        let image = firstCapture(#"(?is)<meta\s+[^>]*property=[\"']og:image[\"'][^>]*content=[\"']([^\"']*)[\"'][^>]*>"#, in: html, group: 1)
            ?? firstCapture(#"(?is)<img\b([^>]*)>"#, in: html, group: 1).flatMap { attribute("src", in: $0) }
            ?? ""
        let description = firstCapture(#"(?is)<meta\s+[^>]*name=[\"']description[\"'][^>]*content=[\"']([^\"']*)[\"'][^>]*>"#, in: html, group: 1)
            ?? firstCapture(#"(?is)<p\b[^>]*>(.*?)</p>"#, in: html, group: 1).map(text)
            ?? ""

        let video = Movie.Video(id: vodID, name: title)
        var enriched = video
        enriched.pic = absoluteImage(image, baseURL: url)
        enriched.des = description
        enriched.year = firstCapture(#"(?:19|20)\d{2}"#, in: html, group: 0) ?? ""
        enriched.sourceKey = "cz4k"

        var episodes: [VodInfo.Episode] = []
        var seen = Set<String>()
        let anchorPattern = try! NSRegularExpression(pattern: #"(?is)<a\b([^>]*?)>(.*?)</a\s*>"#)
        for match in anchorPattern.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else { continue }
            let attrs = String(html[attrsRange])
            let body = String(html[bodyRange])
            let href = firstNonEmpty(
                attribute("href", in: attrs),
                attribute("data-href", in: attrs),
                attribute("data-url", in: attrs),
                attribute("data-play", in: attrs),
                firstCapture(#"(?is)(?:play|url|video)\s*\(\s*[\"']([^\"']+)[\"']"#, in: attrs, group: 1)
            )
            guard !href.isEmpty,
                  let episodeURL = resolvedURL(href, relativeTo: url),
                  Cz4kSearchParser.isPlayableURL(episodeURL),
                  seen.insert(episodeURL.absoluteString).inserted else { continue }
            let name = firstNonEmpty(attribute("title", in: attrs), text(body), "第\(episodes.count + 1)集")
            episodes.append(VodInfo.Episode(name: name, url: episodeURL.absoluteString))
            if episodes.count >= 200 { break }
        }
        if episodes.isEmpty,
           let media = firstCapture(#"(?i)(https?:)?//[^\"'<>\s]+\.(?:m3u8|mp4)(?:\?[^\"'<>\s]*)?"#, in: html, group: 0) {
            let resolvedMedia = media.hasPrefix("//") ? "https:" + media : media
            episodes.append(VodInfo.Episode(name: "正片", url: resolvedMedia))
        }
        guard !episodes.isEmpty else { throw SourceError.invalidResponse("厂长详情页没有找到可播放剧集") }
        let playURL = episodes.map { "\($0.name)$\($0.url)" }.joined(separator: "#")
        return VodInfo.from(video: enriched, playFrom: "厂长线路", playUrl: playURL)
    }

    private static func fetch(_ url: String) async throws -> String {
        #if os(iOS)
        guard let target = URL(string: url) else { throw SourceError.invalidApiUrl(url) }
        return try await Cz4kBrowserSession.loadHTML(target)
        #else
        try await NetworkManager.shared.getString(from: url, headers: headers, timeout: 60, maxRetries: 0)
        #endif
    }

    private static func resolvedURL(_ value: String, relativeTo base: URL) -> URL? {
        URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL
    }

    private static func attribute(_ name: String, in value: String) -> String? {
        let pattern = #"(?is)\b\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return nil
        }
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: value) else { continue }
            let result = decodeEntities(String(value[range])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty { return result }
        }
        return nil
    }

    private static func text(_ html: String) -> String {
        let withoutScripts = html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        let withoutTags = withoutScripts.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func absoluteImage(_ value: String, baseURL: URL) -> String {
        guard !value.isEmpty else { return "" }
        return resolvedURL(value, relativeTo: baseURL)?.absoluteString ?? value
    }

    private static func firstCapture(_ pattern: String, in value: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: value) else { return nil }
        return String(value[range])
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

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
}

#if os(iOS)
private struct Cz4kBrowserPage: Sendable {
    let html: String
    let mediaURLs: [String]
    let mediaCookies: [String: String]
    let isHLSPlaylist: Bool

    func cookieHeader(for mediaURL: String) -> String? {
        let normalizedMediaURL = KktvsResponseNormalizer.normalizeMediaURL(mediaURL)
        if let exact = mediaCookies[normalizedMediaURL] { return exact }
        guard let target = URL(string: mediaURL), let host = target.host?.lowercased() else { return nil }
        return mediaCookies.first { key, _ in
            guard let candidate = URL(string: key), let candidateHost = candidate.host?.lowercased() else {
                return false
            }
            return candidateHost == host && candidate.path == target.path
        }?.value
    }
}

@MainActor
private final class Cz4kBrowserSession: NSObject, WKNavigationDelegate {
    private static let userAgent = PlaybackRequestHeaderPolicy.cz4kBrowserUserAgent
    private static let timeout: TimeInterval = 60
    private static let mediaWaitTimeout: TimeInterval = 24

    private let requestURL: URL
    private let requestHeaders: [String: String]
    private let referer: String?
    private let waitForMedia: Bool
    private let webView: WKWebView
    private let hostView: UIView
    private var continuation: CheckedContinuation<Cz4kBrowserPage, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var finished = false
    private let startedAt = Date()

    private init(
        url: URL,
        headers: [String: String],
        referer: String?,
        waitForMedia: Bool,
        webView: WKWebView,
        hostView: UIView
    ) {
        requestURL = url
        requestHeaders = headers
        self.referer = referer
        self.waitForMedia = waitForMedia
        self.webView = webView
        self.hostView = hostView
    }

    static func loadHTML(_ url: URL, headers: [String: String] = [:]) async throws -> String {
        (try await loadPage(url, headers: headers, waitForMedia: false)).html
    }

    static func loadPage(
        _ url: URL,
        headers: [String: String] = [:],
        referer: String? = nil,
        waitForMedia: Bool
    ) async throws -> Cz4kBrowserPage {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw SourceError.invalidApiUrl(url.absoluteString)
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?.windows
            .first(where: \.isKeyWindow) else {
            throw SourceError.invalidResponse("厂长搜索需要可用的应用窗口，请返回应用后重试")
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.customUserAgent = userAgent
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        hostView.alpha = 0
        hostView.isUserInteractionEnabled = false
        hostView.accessibilityElementsHidden = true
        hostView.addSubview(webView)
        window.addSubview(hostView)

        let session = Cz4kBrowserSession(
            url: url,
            headers: headers,
            referer: referer,
            waitForMedia: waitForMedia,
            webView: webView,
            hostView: hostView
        )
        webView.navigationDelegate = session
        return try await session.load()
    }

    private func load() async throws -> Cz4kBrowserPage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Self.timeout))
                    guard let self, !self.finished else { return }
                    self.finish(.failure(SourceError.invalidResponse(
                        "厂长网页验证尚未完成，请稍后重试"
                    )))
                }
                var request = URLRequest(url: requestURL, timeoutInterval: Self.timeout)
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(
                    referer ?? PlaybackRequestHeaderPolicy.cz4kReferer,
                    forHTTPHeaderField: "Referer"
                )
                requestHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                webView.load(request)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleInspection()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func scheduleInspection() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard let self, !self.finished else { return }
            self.inspectPage()
        }
    }

    private func inspectPage() {
        let autoplayScript = waitForMedia ? """
          document.querySelectorAll('video').forEach(function(video) {
            if (!video.__cz4kAutoplayAttempted) {
              video.__cz4kAutoplayAttempted = true;
              video.muted = true;
              var result = video.play();
              if (result && result.catch) result.catch(function() {});
            }
          });
          try {
            if (typeof window.jwplayer === 'function') {
              var player = window.jwplayer();
              if (player && player.play) player.play(true);
            }
          } catch (_) {}
        """ : ""
        let script = """
        (function() {
          var title = document.title || '';
          var text = (document.body && document.body.innerText) || '';
          var mediaURLs = [];
          document.querySelectorAll('video, source').forEach(function(node) {
            var value = node.currentSrc || node.src || node.getAttribute('src') || '';
            if (value) mediaURLs.push(value);
          });
          performance.getEntriesByType('resource').forEach(function(entry) {
            if (/\\.(m3u8|mp4|mpd|flv|mkv|webm|mov|ts|m4s)(?:[?#]|$)/i.test(entry.name)) {
              mediaURLs.push(entry.name);
            }
          });
          document.querySelectorAll('iframe[src], embed[src]').forEach(function(node) {
            if (node.src) mediaURLs.push(node.src);
          });
        \(autoplayScript)
          mediaURLs = Array.from(new Set(mediaURLs));
          var playlistText = text.trim();
          if (playlistText.charCodeAt(0) === 65279) playlistText = playlistText.slice(1);
          var isHLSPlaylist = playlistText.indexOf('#EXTM3U') === 0;
          if (isHLSPlaylist) mediaURLs.unshift(location.href);
          var challengeWidget = !!document.querySelector('cap-widget');
          var challengeText = /雷池|safeline|安全检查|访问验证|请稍候|正在验证|验证中|验证失败|checking your browser|verifying you are human|403 forbidden|access denied|人机验证/i.test(title + ' ' + text);
          return JSON.stringify({html: document.documentElement ? document.documentElement.outerHTML : '', mediaURLs: mediaURLs, challenge: challengeWidget || challengeText, textLength: text.length, isHLSPlaylist: isHLSPlaylist});
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, !self.finished else { return }
            if let error {
                self.finish(.failure(error))
                return
            }
            guard let json = value as? String,
                  let data = json.data(using: .utf8),
                  let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.scheduleInspection()
                return
            }
            if page["challenge"] as? Bool == true {
                self.scheduleInspection()
                return
            }
            let html = page["html"] as? String ?? ""
            let textLength = page["textLength"] as? Int ?? 0
            let mediaURLs = page["mediaURLs"] as? [String] ?? []
            let isHLSPlaylist = page["isHLSPlaylist"] as? Bool ?? false
            let pageHasTarget = !mediaURLs.isEmpty || KktvsResponseNormalizer.extractMediaURL(
                from: html,
                baseURL: self.webView.url?.absoluteString ?? self.requestURL.absoluteString
            ) != nil
            guard !html.isEmpty, textLength > 0 || pageHasTarget else {
                self.scheduleInspection()
                return
            }
            if self.waitForMedia && !pageHasTarget && Date().timeIntervalSince(self.startedAt) < Self.mediaWaitTimeout {
                self.scheduleInspection()
                return
            }
            self.collectMediaCookies(for: mediaURLs, html: html, isHLSPlaylist: isHLSPlaylist)
        }
    }

    private func collectMediaCookies(for mediaURLs: [String], html: String, isHLSPlaylist: Bool) {
        let pageURL = webView.url?.absoluteString ?? requestURL.absoluteString
        var candidates = mediaURLs
        if let extracted = KktvsResponseNormalizer.extractMediaURL(from: html, baseURL: pageURL) {
            candidates.append(extracted)
        }
        let uniqueCandidates = Array(Set(candidates.compactMap { value -> String? in
            let normalized = KktvsResponseNormalizer.normalizeMediaURL(value)
            guard let url = URL(string: normalized),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else { return nil }
            return url.absoluteString
        }))
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                var cookieHeaders: [String: String] = [:]
                for candidate in uniqueCandidates {
                    guard let url = URL(string: candidate) else { continue }
                    let matching = cookies.filter { cookie in
                        Self.cookie(cookie, matches: url)
                    }
                    guard !matching.isEmpty else { continue }
                    cookieHeaders[candidate] = matching
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")
                }
                self.finish(.success(Cz4kBrowserPage(
                    html: html,
                    mediaURLs: mediaURLs,
                    mediaCookies: cookieHeaders,
                    isHLSPlaylist: isHLSPlaylist
                )))
            }
        }
    }

    private static func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let rawDomain = cookie.domain.lowercased()
        let isDomainCookie = rawDomain.hasPrefix(".")
        let domain = rawDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host == domain || (isDomainCookie && host.hasSuffix(".\(domain)")),
              !cookie.isSecure || url.scheme?.lowercased() == "https",
              cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == cookiePath
            || requestPath.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
    }

    private func finish(_ result: Result<Cz4kBrowserPage, Error>) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        pollTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        hostView.removeFromSuperview()
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
#endif
