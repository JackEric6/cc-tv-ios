import Foundation

@main
struct VerifyDanmuMatchAPI {
    static func main() throws {
        precondition(DanmuMatchRequestPolicy.fileName(title: "沉默的荣耀", episode: "第1集") == "沉默的荣耀 S01E01")
        precondition(DanmuMatchRequestPolicy.fileName(title: "剧名", episode: "S02E3") == "剧名 S02E03")
        precondition(DanmuMatchRequestPolicy.fileName(title: "剧名", episode: "第2季 第12集") == "剧名 S02E12")
        precondition(DanmuMatchRequestPolicy.fileName(title: "剧名", episode: "第十集") == "剧名 S01E10")
        precondition(DanmuMatchRequestPolicy.fileName(title: "电影", episode: "") == "电影")

        let body = try JSONSerialization.data(withJSONObject: ["fileName": "沉默的荣耀 S01E01"])
        let request = try JSONSerialization.jsonObject(with: body) as? [String: String]
        precondition(request?["fileName"] == "沉默的荣耀 S01E01")

        let response = try JSONSerialization.data(withJSONObject: [
            "isMatched": true,
            "matches": [[
                "animeTitle": "沉默的荣耀",
                "episodeTitle": "第1集",
                "url": "https://www.iqiyi.com/v_uf7dtof1l4.html"
            ]]
        ])
        let matches = DanmuMatchRequestPolicy.parseMatches(String(decoding: response, as: UTF8.self))
        precondition(matches.count == 1)
        precondition(matches[0].displayTitle == "沉默的荣耀 第1集")
        let commentURL = DanmuMatchRequestPolicy.commentURL(
            baseURL: "https://danmu.example/token",
            videoURL: matches[0].videoURL
        )
        let components = URLComponents(string: commentURL ?? "")
        precondition(components?.path == "/token/api/v2/comment")
        precondition(components?.queryItems?.first(where: { $0.name == "url" })?.value == matches[0].videoURL)
        precondition(components?.queryItems?.first(where: { $0.name == "format" })?.value == "json")

        let unmatched = #"{"isMatched":false,"matches":[{"url":"https://example.com/a"}]}"#
        precondition(DanmuMatchRequestPolicy.parseMatches(unmatched).isEmpty)
        print("DANMU MATCH API CHECKS PASSED")
    }
}
