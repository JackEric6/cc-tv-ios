import Foundation

@main
struct VerifyAdultContentFilter {
    static func main() {
        let direct = Movie.Video(id: "1", name: "示例伦理片", category: "电影")
        let category = Movie.Video(id: "2", name: "普通片名", category: "理论片")
        let crossSource = Movie.Video(id: "3", name: "示例 1080P [国语]", sourceKey: "ffzy")
        let otherSeason = Movie.Video(id: "4", name: "示例第二季", sourceKey: "xgzy")
        let eighteen = Movie.Video(id: "5", name: "成人片 18 +", sourceKey: "bfzy")

        guard AdultContentFilter.containsMarker("18+") else { fatalError("18+ 未命中") }
        guard AdultContentFilter.containsMarker("18 +") else { fatalError("18 + 未命中") }
        guard AdultContentFilter.isAdultContent(direct) else { fatalError("标题规则未命中") }
        guard AdultContentFilter.isAdultContent(category) else { fatalError("分类规则未命中") }
        guard AdultContentFilter.isAdultContent(eighteen) else { fatalError("数字规则未命中") }

        let visible = AdultContentFilter.filtered(
            [direct, category, crossSource, otherSeason, eighteen],
            enabled: true
        )
        guard visible.contains(otherSeason), !visible.contains(direct), !visible.contains(category),
              !visible.contains(crossSource), !visible.contains(eighteen) else {
            fatalError("跨源标题过滤或季数区分失败")
        }

        let disabled = AdultContentFilter.filtered([direct, category, crossSource, otherSeason, eighteen], enabled: false)
        guard disabled.count == 5 else { fatalError("会话关闭后不应继续过滤") }
        print("ADULT CONTENT FILTER CHECKS PASSED")
    }
}
