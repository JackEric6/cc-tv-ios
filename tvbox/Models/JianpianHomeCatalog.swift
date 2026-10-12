import Foundation

enum JianpianHomeCatalog {
    // 荐片 API 的分类 ID：1 电影、2 电视剧、3 动漫、4 综艺。
    static let sorts = [
        MovieSort.SortData(id: "2", name: "电视剧"),
        MovieSort.SortData(id: "1", name: "电影"),
        MovieSort.SortData(id: "4", name: "综艺"),
        MovieSort.SortData(id: "3", name: "动漫")
    ]
}
