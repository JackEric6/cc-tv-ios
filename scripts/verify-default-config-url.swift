import Foundation

@main
struct VerifyDefaultConfigURL {
    static func main() {
        precondition(DefaultConfigURLPolicy.migratedURL("") == "")
        precondition(DefaultConfigURLPolicy.migratedURL(DefaultConfigURLPolicy.legacyURL) == DefaultConfigURLPolicy.bundledURL)
        precondition(DefaultConfigURLPolicy.migratedURL(
            "https://ghproxy.net/https://raw.githubusercontent.com/JackEric6/movie/refs/heads/xgzy-config-20260922/movie2_xgzy_all?raw=1"
        ) == DefaultConfigURLPolicy.bundledURL)
        precondition(DefaultConfigURLPolicy.migratedURL(
            "https://config.example.com/custom.json"
        ) == "https://config.example.com/custom.json")
        print("DEFAULT CONFIG URL MIGRATION CHECKS PASSED")
    }
}
