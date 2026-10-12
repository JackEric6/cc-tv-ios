import Foundation

@main
struct VerifyDanmuCandidatePolicy {
    static func main() {
        let shawshankMovie = DanmuSearchResult(
            name: "肖申克的救赎(1994)【电影】from 360 【youku】肖申克的救赎(1994)",
            url: "https://comments.example/movie",
            isBuiltin: true,
            mediaType: "电影"
        )
        let shawshankPV = DanmuSearchResult(
            name: "肖申克的救赎(1994)【电影】from bilibili 【bilibili1】 PV 希望让你重获自由",
            url: "https://comments.example/pv",
            isBuiltin: true,
            mediaType: "电影"
        )
        let otherMovie = DanmuSearchResult(
            name: "阿甘正传(1994)【电影】正片",
            url: "https://comments.example/forrest",
            isBuiltin: true,
            mediaType: "电影"
        )
        let movieCandidates = DanmuCandidatePolicy.automaticLoadCandidates(
            [shawshankPV, otherMovie, shawshankMovie],
            title: "肖申克的救赎",
            episode: "第1集"
        )
        precondition(movieCandidates == [shawshankMovie])

        let episodeOne = DanmuSearchResult(
            name: "沉默的荣耀(2025)【电视剧】 第1集 吴石决定只身赴台",
            url: "https://comments.example/episode-1",
            isBuiltin: true,
            mediaType: "电视剧"
        )
        let episodeTen = DanmuSearchResult(
            name: "沉默的荣耀(2025)【电视剧】 第10集",
            url: "https://comments.example/episode-10",
            isBuiltin: true,
            mediaType: "电视剧"
        )
        let episodeCandidates = DanmuCandidatePolicy.automaticLoadCandidates(
            [episodeTen, episodeOne],
            title: "沉默的荣耀",
            episode: "第1集"
        )
        precondition(episodeCandidates == [episodeOne])

        precondition(DanmuCandidatePolicy.isPromotional("【bilibili】 PV1 希望让你重获自由"))
        precondition(DanmuCandidatePolicy.isPromotional("Feature trailer"))
        print("DANMU CANDIDATE POLICY CHECKS PASSED")
    }
}
