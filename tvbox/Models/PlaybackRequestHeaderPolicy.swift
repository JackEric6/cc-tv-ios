import Foundation

enum PlaybackRequestHeaderPolicy {
    private static let cmsSourceReferers: [String: String] = [
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
        if let referer = cmsSourceReferers[key] {
            result["Referer"] = referer
        }
        return result
    }
}
