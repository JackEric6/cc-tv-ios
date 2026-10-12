import Foundation

enum JianpianHomeCatalog {
    // Mirrors the local CMS category JSON emitted by Android's Jianpian adapter.
    static let sorts = [
        MovieSort.SortData(id: "1", name: "电影"),
        MovieSort.SortData(id: "2", name: "电视剧"),
        MovieSort.SortData(id: "3", name: "综艺"),
        MovieSort.SortData(id: "4", name: "动漫")
    ]
}
