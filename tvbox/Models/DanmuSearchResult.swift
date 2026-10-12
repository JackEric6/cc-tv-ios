import Foundation

public struct DanmuSearchResult: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: String
    public let isBuiltin: Bool
    public let mediaType: String?

    public var id: String { url }

    public init(name: String, url: String, isBuiltin: Bool, mediaType: String? = nil) {
        self.name = name.isEmpty ? url : name
        self.url = url
        self.isBuiltin = isBuiltin
        self.mediaType = mediaType
    }
}
