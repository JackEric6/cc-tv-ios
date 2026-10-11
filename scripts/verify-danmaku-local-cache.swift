import Foundation

@main
struct VerifyDanmakuLocalCache {
    static func main() async throws {
        let titleA = DanmakuCacheKey.make(title: "  沉默的荣耀（1080P） ", episode: "第01集")
        let titleB = DanmakuCacheKey.make(title: "沉默的荣耀", episode: "EP1 正片")
        precondition(titleA == titleB)
        precondition(
            DanmakuCacheKey.make(title: "剧名", episode: "S01E02")
                == DanmakuCacheKey.make(title: "剧名", episode: "第1季第2集")
        )
        precondition(
            DanmakuCacheKey.make(title: "剧名", episode: "第二十一集")
                == DanmakuCacheKey.make(title: "剧名", episode: "EP21")
        )
        precondition(
            DanmakuCacheKey.make(title: "剧名", episode: "S01E02")
                != DanmakuCacheKey.make(title: "剧名", episode: "S02E02")
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("danmaku-cache-test-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = try require(titleA)
        let cue = DanmuCue(time: 12.5, type: 1, size: 25, color: 0xFFFFFF, text: "已缓存弹幕")
        let cache = DanmakuLocalCache(fileURL: fileURL, lifetime: 60, maximumEntries: 2, maximumTotalCues: 10)
        await cache.store([cue], for: key)
        let firstRead = await cache.cues(for: key)
        precondition(firstRead == [cue])

        let reopenedCache = DanmakuLocalCache(fileURL: fileURL, lifetime: 60)
        let persistedRead = await reopenedCache.cues(for: key)
        precondition(persistedRead == [cue])

        let expiredRead = await reopenedCache.cues(for: key, now: Date().addingTimeInterval(120))
        precondition(expiredRead == nil)
        print("DANMAKU CROSS-SOURCE CACHE CHECKS PASSED")
    }

    private static func require(_ value: String?) throws -> String {
        guard let value else { throw NSError(domain: "DanmakuCacheTest", code: 1) }
        return value
    }
}
