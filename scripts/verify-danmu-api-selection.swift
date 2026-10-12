import Foundation

@main
struct VerifyDanmuAPISelection {
    static func main() {
        let builtin = "https://logvardanmu.konfan.cn/87654321"
        precondition(DanmuAPISelectionPolicy.candidates(
            explicit: nil,
            useDefault: false,
            saved: "https://old.example/danmu",
            configured: "https://config.example/danmu",
            builtin: builtin,
            fallbacks: ["https://saas-oa.shyeguang.cn", "https://api.danmu.icu"]
        ) == ["https://old.example/danmu", builtin, "https://saas-oa.shyeguang.cn", "https://api.danmu.icu"])

        precondition(DanmuAPISelectionPolicy.candidates(
            explicit: nil,
            useDefault: true,
            saved: "https://old.example/danmu",
            configured: "https://config.example/danmu",
            builtin: builtin,
            fallbacks: ["https://saas-oa.shyeguang.cn", "https://api.danmu.icu"]
        ) == [builtin, "https://saas-oa.shyeguang.cn", "https://api.danmu.icu"])

        precondition(DanmuAPISelectionPolicy.candidates(
            explicit: " https://custom.example/danmu ",
            useDefault: true,
            saved: nil,
            configured: nil,
            builtin: builtin,
            fallbacks: ["https://saas-oa.shyeguang.cn", "https://api.danmu.icu"]
        ) == ["https://custom.example/danmu", builtin, "https://saas-oa.shyeguang.cn", "https://api.danmu.icu"])

        precondition(DanmuAPISelectionPolicy.candidates(
            explicit: builtin,
            useDefault: false,
            saved: nil,
            configured: nil,
            builtin: builtin
        ) == [builtin])

        print("DANMU API FALLBACK CHECKS PASSED")
    }
}
