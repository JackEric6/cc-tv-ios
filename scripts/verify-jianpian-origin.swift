import Foundation

@main
struct VerifyJianpianOrigin {
    static func main() {
        precondition(JianpianOriginPolicy.normalize("fan123.hzhnl.com") == "https://fan123.hzhnl.com")
        precondition(JianpianOriginPolicy.normalize("http://api.example.com") == nil)
        precondition(JianpianOriginPolicy.normalize("https://api.example.com/vod") == nil)
        precondition(JianpianOriginPolicy.normalize("\"\"") == nil)
        precondition(JianpianOriginPolicy.discoveryURL.contains("config.txt"))

        let candidates = JianpianOriginPolicy.candidates(
            preferred: "https://fan123.hzhnl.com/",
            discoveredServers: "\"one.example.com,two.example.com\"\none.example.com"
        )
        precondition(Array(candidates.prefix(3)) == [
            "https://fan123.hzhnl.com",
            "https://one.example.com",
            "https://two.example.com"
        ])
        precondition(candidates[3] == "https://bdgnbrws.com")
        precondition(Set(candidates).count == candidates.count)
        precondition(JianpianOriginPolicy.shouldFailover(statusCode: 404))
        precondition(JianpianOriginPolicy.shouldFailover(statusCode: 429))
        precondition(JianpianOriginPolicy.shouldFailover(statusCode: 503))
        precondition(!JianpianOriginPolicy.shouldFailover(statusCode: 403))
        precondition(!JianpianOriginPolicy.shouldFailover(statusCode: 422))
        print("JIANPIAN ORIGIN CHECKS PASSED")
    }
}
