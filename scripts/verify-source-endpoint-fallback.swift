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
        print("SOURCE ENDPOINT FALLBACK CHECKS PASSED")
    }
}
