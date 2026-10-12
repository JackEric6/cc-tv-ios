@main
enum VerifyJianpianHome {
    static func main() {
        let sorts = JianpianHomeCatalog.sorts
        precondition(sorts.map(\.name) == ["电视剧", "电影", "综艺", "动漫"])
        precondition(sorts.map(\.id) == ["2", "1", "4", "3"])
        print("JIANPIAN HOME CATEGORY ORDER CHECK PASSED")
    }
}
