import Foundation

enum PlaybackRequestHeaderPolicy {
    private static let cmsSourceReferers: [String: String] = [
        "xgzy": "https://xgzy.tv/",
        "zuida": "https://zuidazy.co/",
        "bdzy": "https://bdzy.tv/",
        "modu": "https://moduzy.com/",
        "xinlang": "https://xinlangzy.com/",
        "maoyan": "https://www.maoyanzy.com/",
        "iqiyi": "https://iqiyizy.com/",
        "suboziyuan": "https://www.suboziyuan.net/",
        "haohua": "https://haohuazy.com/",
        "fhw88": "https://ffzy5.tv/",
        "ffzy": "https://ffzy5.tv/",
        "lzi": "https://lzizy.net/",
        "sony": "https://suonizy.net/",
        "hongniu": "https://hongniuzy.com/",
        "wujin": "https://wujinzy.com/",
        "jisu": "https://jisuzy1.com/",
        "yaya": "https://yayazy.com/",
        "niuniu": "https://niuniuzy.cc/",
        "shandian": "https://shandianzy.com/",
        "jinying": "https://jinyingzy.com/",
        "yhzy": "https://yhzy.cc/",
        "guangsu": "https://www.guangsuzy.com/",
        "huya": "https://huyazy.com/",
        "360zy": "https://360zy.com/",
        "juliang": "https://juliang.app/",
        "yparse": "https://yparse.com/",
        "ikunzy": "https://ikunzy.com/",
        "cz4k": "https://www.cz4k.com/",
        "qiumu": "https://old.sliiic.org/",
        "meitan": "https://www.hmjy100.com/",
        "jingyan": "https://www.wljingyan.com/",
        "kaida": "https://www.kdndt.net/",
        "shuicao": "http://www.knshuichuli.com/",
        "hongguo": "https://m.syshuoyuan.com/",
        "laoniu": "https://shanghai.365che.net/",
        "ningmeng": "https://www.nmgflw.com/",
        "xingchen": "http://www.chgxdq.com/",
        "qingpingguo": "https://yz.sdhfcj.com/",
        "zhongxing": "https://www.sczxsx.com/",
        "haier": "https://www.nbhaierxin.com/",
        "huilv": "https://www.zzhuilv.cn/",
        "shiji": "http://m.sjtx-oa.com/",
        "cechi": "http://www.lanyajc.com/",
        "kuaikan": "http://www.ikang.org/",
        "wushuang": "http://www.fjsycjs.com/",
        "zanpian": "https://www.zanpian.org/",
        "ys88": "https://www.88ystv.com/"
    ]

    static let androidDefaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    static let androidCMSPlaybackUserAgent =
        "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"
    static let cz4kBrowserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let cz4kReferer = "https://www.cz4k.com/"

    static func appliesToCMSPlayback(sourceType: Int) -> Bool {
        sourceType == 0 || sourceType == 1
    }

    static func applyingCMSPlaybackHeaders(
        to headers: [String: String],
        sourceKey: String
    ) -> [String: String] {
        let key = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = headers
        result.keys.filter { $0.caseInsensitiveCompare("Referer") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result.keys.filter { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result["User-Agent"] = androidCMSPlaybackUserAgent
        // Match Android playback headers: CMS endpoint Referer mappings belong
        // to catalog requests and must not be copied to media CDN requests.
        if let referer = cmsSourceReferers[key] {
            result["Referer"] = referer
        }
        return result
    }

    static func xiguaMediaReferer(for mediaURL: String) -> String? {
        guard let components = URLComponents(string: mediaURL),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              components.percentEncodedPath.localizedCaseInsensitiveContains(".m3u8") else {
            return nil
        }

        var pathComponents = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)
        if pathComponents.count >= 3,
           pathComponents.suffix(3).map({ $0.lowercased() }) == ["3000k", "hls", "mixed.m3u8"] {
            pathComponents.removeLast(3)
        } else if !pathComponents.isEmpty {
            pathComponents.removeLast()
        }

        var referer = components
        referer.percentEncodedPath = "/" + pathComponents.joined(separator: "/")
        if !referer.percentEncodedPath.hasSuffix("/") {
            referer.percentEncodedPath += "/"
        }
        referer.query = nil
        referer.fragment = nil
        return referer.url?.absoluteString
    }

    static func mediaRefererOverride(sourceKey: String, mediaURL: String) -> String? {
        guard sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("xgzy") == .orderedSame else {
            return nil
        }
        return xiguaMediaReferer(for: mediaURL)
    }

    static func applyingSourceSpecificPlaybackHeaders(
        to headers: [String: String],
        sourceKey: String
    ) -> [String: String] {
        guard sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("cz4k") == .orderedSame else {
            return headers
        }
        var result = headers
        result.keys.filter { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result.keys.filter { $0.caseInsensitiveCompare("Referer") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result["User-Agent"] = cz4kBrowserUserAgent
        result["Referer"] = cz4kReferer
        return result
    }

    static func applyingRefererOverride(_ referer: String?, to headers: [String: String]) -> [String: String] {
        guard let referer = referer?.trimmingCharacters(in: .whitespacesAndNewlines),
              !referer.isEmpty else { return headers }
        var result = headers
        result.keys.filter { $0.caseInsensitiveCompare("Referer") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result["Referer"] = referer
        return result
    }
}
