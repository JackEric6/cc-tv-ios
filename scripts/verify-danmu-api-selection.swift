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
            builtin: builtin
        ) == ["https://old.example/danmu", builtin])

        precondition(DanmuAPISelectionPolicy.candidates(
            explicit: nil,
            useDefault: true,
            saved: "https://old.example/danmu",
            configured: "https://config.example/danmu",
            builtin: builtin
        ) == [builtin])

        precondition(DanmuAPISelectionPolicy.candidates(
            explicit: " https://custom.example/danmu ",
            useDefault: true,
            saved: nil,
            configured: nil,
            builtin: builtin
        ) == ["https://custom.example/danmu", builtin])

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
