import Foundation

enum SourceEndpointRequestPolicy {
    static func candidates(
        for requestURL: String,
        backupAPIs: [String],
        backupDomains: [String]
    ) -> [String] {
        guard let request = URLComponents(string: requestURL) else { return [requestURL] }
        var result: [String] = []
        var seen = Set<String>()

        func append(_ candidate: URLComponents) {
            guard let url = candidate.url?.absoluteString, seen.insert(url).inserted else { return }
            result.append(url)
        }

        append(request)
        for path in alternatePaths(for: request.host?.lowercased() ?? "") {
            var alternate = request
            alternate.path = path
            append(alternate)
        }
        for rawAPI in backupAPIs + knownBackupAPIs(for: request.host?.lowercased() ?? "") {
            guard let base = URLComponents(string: rawAPI.trimmingCharacters(in: .whitespacesAndNewlines)),
                  isHTTP(base) else { continue }
            append(mergingRequestParameters(from: request, into: base))
        }
        for rawDomain in backupDomains {
            guard var base = URLComponents(string: rawDomain.trimmingCharacters(in: .whitespacesAndNewlines)),
                  isHTTP(base) else { continue }
            if base.path.isEmpty || base.path == "/" {
                base.path = request.path
            }
            base = mergingRequestParameters(from: request, into: base)
            append(base)
        }
        return result
    }

    private static func mergingRequestParameters(
        from request: URLComponents,
        into base: URLComponents
    ) -> URLComponents {
        var result = base
        var items = result.queryItems ?? []
        for item in request.queryItems ?? [] {
            items.removeAll { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }
            items.append(item)
        }
        result.queryItems = items.isEmpty ? nil : items
        result.fragment = request.fragment ?? result.fragment
        return result
    }

    private static func isHTTP(_ components: URLComponents) -> Bool {
        ["http", "https"].contains(components.scheme?.lowercased() ?? "")
            && !(components.host ?? "").isEmpty
    }

    private static func alternatePaths(for host: String) -> [String] {
        switch host {
        case "api.ffzyapi.com":
            return [
                "/api.php/provide/vod/",
                "/api.php/provide/vod/from/ffm3u8/at/json/"
            ]
        case "caiji.dyttzyapi.com":
            return [
                "/api.php/provide/vod/from/dyttm3u8/",
                "/api.php/provide/vod/from/dyttm3u8/at/json/"
            ]
        case "caiji.dbzy5.com":
            return [
                "/api.php/provide/vod/",
                "/api.php/provide/vod/from/dbm3u8/at/json/"
            ]
        case "cj.lziapi.com":
            return [
                "/api.php/provide/vod/",
                "/api.php/provide/vod/from/lzyun/"
            ]
        case "cj.ffzyapi.com":
            return [
                "/api.php/provide/vod/",
                "/api.php/provide/vod/from/ffm3u8/"
            ]
        case "haiwaikan.com":
            return ["/api.php/provide/vod/from", "/api.php/provide/vod"]
        case "suoniapi.com":
            return ["/api.php/provide/vod/", "/api.php/provide/vod/at/xml/"]
        case "cj.rycjapi.com":
            return [
                "/api.php/provide/vod/from/rym3u8/",
                "/api.php/provide/vod/from/ryyun/"
            ]
        case "api.xinlangapi.com":
            return [
                "/xinlangapi.php/provide/vod/",
                "/xinlangapi.php/provide/vod/from/xlyun/",
                "/xinlangapi.php/provide/vod/from/xlm3u8/"
            ]
        case "api.yparse.com":
            return ["/api/m3u8/json"]
        case "caiji.maotai999.vip":
            return [
                "/api.php/provide/vod/",
                "/api.php/provide/vod/from/mtm3u8/at/josn/"
            ]
        case "m766.com":
            return ["/api.php/provide/vod/at/json", "/api.php/provide/vod/at/xml"]
        case "ikunzyapi.com":
            return [
                "/api.php/provide/vod/from/ikm3u8/at/json",
                "/api.php/provide/vod/"
            ]
        default:
            return []
        }
    }

    private static func knownBackupAPIs(for host: String) -> [String] {
        switch host {
        case "api.ffzyapi.com":
            return [
                "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8/",
                "https://cj.ffzyapi.com/api.php/provide/vod/"
            ]
        default:
            return []
        }
    }
}
