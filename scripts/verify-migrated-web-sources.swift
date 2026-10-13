import Foundation

extension URL {
    static func posterURL(from raw: String) -> URL? {
        URL(string: raw)
    }
}

struct SourceBean {
    let api: String
    let key: String
    let headers: [String: String]?
}

enum SourceError: Error {
    case invalidApiUrl(String)
    case invalidPlayableURL(String)
    case invalidResponse(String)
}

struct Movie {
    struct Video {
        var id: String
        var name: String
        var pic = ""
        var note = ""
        var year = ""
        var area = ""
        var actor = ""
        var des = ""
        var sourceKey = ""

        init(id: String, name: String, sourceKey: String = "") {
            self.id = id
            self.name = name
            self.sourceKey = sourceKey
        }
    }
}

struct VodInfo {
    struct Episode {
        let name: String
        let url: String
    }

    static func from(video: Movie.Video, playFrom: String, playUrl: String) -> VodInfo { VodInfo() }
}

final class NetworkManager {
    static let shared = NetworkManager()

    func getString(
        from url: String,
        headers: [String: String]?,
        timeout: Int?,
        maxRetries: Int
    ) async throws -> String {
        throw CocoaError(.fileReadUnknown)
    }
}

enum KktvsResponseNormalizer {
    static func extractMediaURL(from body: String, baseURL: String) -> String? { nil }
    static func directMediaURL(_ value: String) -> String? { value.lowercased().contains(".m3u8") ? value : nil }
    static func normalizeMediaURL(_ value: String) -> String { value }
}

@main
struct VerifyMigratedWebSources {
    static func main() throws {
        precondition(
            MigratedWebSourceService.buildIkanbotToken(
                videoID: "936072",
                eToken: "nd44cd4f0ef214c5ceru378be3bb9h128607b14"
            ) == "d44cd4f0f214c5ce378be3bb28607b14"
        )
        precondition(MigratedWebSourceService.buildIkanbotToken(videoID: "1", eToken: "short").isEmpty)

        let resData = [[
            "flag": "gsm3u8",
            "url": "第1集$https://video.example/one.m3u8#第2集$https://video.example/two.m3u8"
        ]]
        let resDataText = String(data: try JSONSerialization.data(withJSONObject: resData), encoding: .utf8)!
        let response = try JSONSerialization.data(withJSONObject: [
            "state": 1,
            "data": ["list": [["resData": resDataText]]]
        ])
        let parsed = MigratedWebSourceService.parseIkanbotSources(String(data: response, encoding: .utf8)!)
        precondition(parsed.0 == ["gsm3u8"])
        precondition(parsed.1 == [
            "第1集$https://video.example/one.m3u8#第2集$https://video.example/two.m3u8"
        ])

        let zanpianHTML = """
        <li><a class="module_play_img" href="/China/chenmoderongyao/">
        <img src="https://img.example/poster.jpg" alt="沉默的荣耀"/>
        <label>共39集 连载至第39集</label></a>
        <div class="play-txt"><h5><a href="/China/chenmoderongyao/"><font>沉默的荣耀</font></a></h5></div></li>
        """
        let cards = MigratedWebSourceService.parseZanpianCards(
            zanpianHTML,
            sourceKey: "zanpian",
            baseURL: URL(string: "https://www.zanpian.org/")!
        )
        precondition(cards.count == 1)
        precondition(cards[0].id == "/China/chenmoderongyao")
        precondition(cards[0].name == "沉默的荣耀")
        precondition(cards[0].pic.isEmpty)

        let nomiSearchHTML = """
        <li><div class="pic"><a href="/vod-detail-id-63541.html"><img data-src="/poster.jpg" alt=""/></a></div>
        <div class="txt"><span class="sTit">沉默的荣耀</span><span class="sDes">主演：于和伟</span></div></li>
        """
        let nomiVideos = NomiSourceService.parseSearchResults(
            nomiSearchHTML,
            sourceKey: "fan_nomi",
            baseURL: URL(string: "https://vip.wwgz.cn:5200")!
        )
        precondition(nomiVideos.count == 1)
        precondition(nomiVideos[0].id == "https://vip.wwgz.cn:5200/vod-detail-id-63541.html")
        precondition(nomiVideos[0].name == "沉默的荣耀")
        precondition(nomiVideos[0].pic == "https://vip.wwgz.cn:5200/poster.jpg")

        let nomiDetailHTML = """
        <div id="leftTabBox"><div class="hd"><ul><li><a>线路①</a></li><li><a>线路②</a></li></ul></div>
        <div class="bd"><div id="monday" class="numList"><ul>
        <li><a href="/vod-play-id-1-src-1-num-3.html">第03集</a></li>
        <li><a href="/vod-play-id-1-src-1-num-2.html">第02集</a></li>
        <li><a href="/vod-play-id-1-src-1-num-1.html">第01集</a></li>
        </ul></div><div id="lzm3u8" class="numList"><ul>
        <li><a href="/vod-play-id-1-src-2-num-2.html">第02集</a></li>
        <li><a href="/vod-play-id-1-src-2-num-1.html">第01集</a></li>
        </ul></div></div></div>
        """
        let nomiLists = NomiSourceService.parseEpisodeLists(
            nomiDetailHTML,
            baseURL: URL(string: "https://vip.wwgz.cn:5200")!
        )
        precondition(nomiLists.map(\.name) == ["线路①", "线路②"])
        precondition(nomiLists[0].entries == [
            "第01集$https://vip.wwgz.cn:5200/vod-play-id-1-src-1-num-1.html",
            "第02集$https://vip.wwgz.cn:5200/vod-play-id-1-src-1-num-2.html",
            "第03集$https://vip.wwgz.cn:5200/vod-play-id-1-src-1-num-3.html"
        ])
        let selectedNomiEpisode = NomiSourceService.selectedEpisodeMediaURL(
            in: "var mac_url='第01集$https://cdn.example/one.m3u8#第02集$https://cdn.example/two.m3u8';",
            episodeURL: "https://vip.wwgz.cn:5200/vod-play-id-1-src-1-num-2.html"
        )
        precondition(selectedNomiEpisode == "https://cdn.example/two.m3u8")
        let nomiHeaders = NomiSourceService.requestHeaders(
            source: SourceBean(api: "https://vip.wwgz.cn:5200", key: "fan_nomi", headers: ["User-Agent": "old"]),
            referer: "https://vip.wwgz.cn:5200/vod-detail-id-1.html"
        )
        precondition(nomiHeaders["User-Agent"]?.contains("iPhone") == true)
        precondition(nomiHeaders["Referer"] == "https://vip.wwgz.cn:5200/vod-detail-id-1.html")

        let suggestions = SearchSuggestionService.parse("""
        {"code":"A00000","data":[{"name":"沉默的荣耀"},{"title":"荣耀之后"},{"name":"沉默的荣耀"}]}
        """)
        precondition(suggestions == ["沉默的荣耀", "荣耀之后"])
        print("MIGRATED WEB SOURCE AND SEARCH SUGGESTION CHECKS PASSED")
    }
}
