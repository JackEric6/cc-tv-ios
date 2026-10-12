import Foundation

enum CMSRequestHeaderPolicy {
    static let androidUserAgent =
        "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"

    private static let referers: [String: String] = [
        "caiji.xgzyapi.com": "https://xgzy.tv/",
        "api.ffzyapi.com": "https://ffzy5.tv/",
        "cj.ffzyapi.com": "https://ffzy5.tv/",
        "cj.lziapi.com": "https://lzizy.net/",
        "suoniapi.com": "https://suonizy.net/",
        "haiwaikan.com": "https://haiwaikan.com/",
        "api.kuaifan.tv": "https://kuaifan.tv/",
        "leshiapi.com": "https://leshiapi.com/",
        "www.hongniuzy2.com": "https://hongniuzy.com/",
        "api.wujinapi.me": "https://wujinzy.com/",
        "jszyapi.com": "https://jisuzy1.com/",
        "cj.yayazy.net": "https://yayazy.com/",
        "api.niuniuzy.me": "https://niuniuzy.cc/",
        "sdzyapi.com": "https://shandianzy.com/",
        "jyzyapi.com": "https://jinyingzy.com/",
        "m3u8.apiyhzy.com": "https://yhzy.cc/",
        "api.guangsuapi.com": "https://www.guangsuzy.com/",
        "www.huyaapi.com": "https://huyazy.com/",
        "360zyzz.com": "https://360zy.com/",
        "api.juliang.live": "https://juliang.app/",
        "iqiyizyapi.com": "https://iqiyizy.com/",
        "api.maoyanapi.top": "https://www.maoyanzy.com/",
        "caiji.dbzy5.com": "https://dbzy.tv/",
        "api.okzyw.net": "https://www.zzzypro.com/",
        "bfzyapi.com": "https://bfzy2.tv/",
        "tyyszyapi.com": "https://tyyszy.com/",
        "zuidazy.co": "https://zuidazy.co/",
        "api.yzzy-api.com": "https://yzzy.tv/",
        "caiji.kuaichezy.org": "https://kuaichezy.com/",
        "hhzyapi.com": "https://haohuazy.com/",
        "api.xinlangapi.com": "https://xinlangzy.com/",
        "api.wsyzy.net": "https://www.wsyzy.cc/",
        "caiji.dyttzyapi.com": "https://dyttzy.tv/",
        "api.ukuapi88.com": "https://ukuzy.com/",
        "www.mdzyapi.com": "https://moduzy.com/",
        "subocj.com": "https://www.suboziyuan.net/",
        "api.apibdzy.com": "https://bdzy.tv/",
        "cdn.dzzyapi.com": "https://dzzy.com/",
        "cj.rycjapi.com": "https://ryzy.tv/",
        "api.yparse.com": "https://yparse.com/",
        "caiji.maotai999.vip": "https://mtzy0.com/",
        "m766.com": "https://m766.com/",
        "ikunzyapi.com": "https://ikunzy.com/"
    ]

    static func headers(for requestURL: String, configured: [String: String]?) -> [String: String] {
        var headers = [
            "User-Agent": androidUserAgent,
            "Accept": "application/json,text/plain,*/*"
        ]
        if let components = URLComponents(string: requestURL),
           let host = components.host?.lowercased(),
           let referer = referers[host] {
            headers["Referer"] = referer
        } else if let components = URLComponents(string: requestURL),
                  let scheme = components.scheme,
                  let host = components.host {
            headers["Referer"] = "\(scheme)://\(host)/"
        }
        configured?.forEach { key, value in
            headers.keys
                .filter { $0.caseInsensitiveCompare(key) == .orderedSame }
                .forEach { headers.removeValue(forKey: $0) }
            headers[key] = value
        }
        return headers
    }

    static func sourceReferer(for sourceAPI: String) -> String? {
        guard let host = URLComponents(string: sourceAPI)?.host?.lowercased() else { return nil }
        return referers[host]
    }
}
