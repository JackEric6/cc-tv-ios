import Foundation

@main
struct VerifySourceEndpointFallback {
    static func main() {
        let candidates = SourceEndpointRequestPolicy.candidates(
            for: "https://primary.example/api/vod?token=abc&ac=detail&wd=old",
            backupAPIs: ["https://backup.example/api/vod?key=preserved"],
            backupDomains: ["https://mirror.example/", "https://backup.example/api/vod?key=preserved"]
        )
        precondition(candidates.count == 3)
        precondition(candidates[0] == "https://primary.example/api/vod?token=abc&ac=detail&wd=old")

        let api = URLComponents(string: candidates[1])!
        precondition(api.host == "backup.example")
        precondition(api.path == "/api/vod")
        precondition(api.queryItems?.first(where: { $0.name == "key" })?.value == "preserved")
        precondition(api.queryItems?.first(where: { $0.name == "wd" })?.value == "old")

        let mirror = URLComponents(string: candidates[2])!
        precondition(mirror.host == "mirror.example")
        precondition(mirror.path == "/api/vod")
        precondition(mirror.queryItems?.first(where: { $0.name == "token" })?.value == "abc")
        precondition(mirror.queryItems?.first(where: { $0.name == "ac" })?.value == "detail")

        let quantum = SourceEndpointRequestPolicy.candidates(
            for: "https://cj.lziapi.com/api.php/provide/vod/from/lzm3u8/?ac=detail&wd=抓特务",
            backupAPIs: [],
            backupDomains: []
        )
        precondition(quantum.count == 3)
        precondition(quantum[1].contains("/api.php/provide/vod/?"))
        precondition(quantum[2].contains("/api.php/provide/vod/from/lzyun/?"))

        let ffzy = SourceEndpointRequestPolicy.candidates(
            for: "https://api.ffzyapi.com/api.php/provide/vod/from/ffm3u8/?ac=detail&wd=test",
            backupAPIs: [],
            backupDomains: []
        )
        precondition(ffzy.contains { $0.contains("cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8/") })
        precondition(ffzy.contains { $0.contains("api.ffzyapi.com/api.php/provide/vod/?ac=detail&wd=test") })

        let dytt = SourceEndpointRequestPolicy.candidates(
            for: "https://caiji.dyttzyapi.com/api.php/provide/vod/?ac=detail&wd=%E6%8A%93%E7%89%B9%E5%8A%A1",
            backupAPIs: [],
            backupDomains: []
        )
        precondition(dytt.contains {
            $0.contains("/api.php/provide/vod/from/dyttm3u8/?ac=detail")
                && $0.contains("wd=%E6%8A%93%E7%89%B9%E5%8A%A1")
        })

        let xintong = SourceEndpointRequestPolicy.candidates(
            for: "https://cj.ffzyapi.com/api.php/provide/vod/?ac=detail&wd=test",
            backupAPIs: [],
            backupDomains: []
        )
        precondition(xintong.count == 2)
        precondition(xintong[1].contains("/api.php/provide/vod/from/ffm3u8/?ac=detail&wd=test"))
        print("SOURCE ENDPOINT FALLBACK CHECKS PASSED")
    }
}
