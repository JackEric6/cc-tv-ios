import Foundation

enum JianpianOriginPolicy {
    static let preferredOrigin = "https://fan123.hzhnl.com"
    static let discoveryURL = "https://ssopj-1462720388.cos.accelerate.myqcloud.com/config.txt"

    private static let fallbackOrigins = [
        "https://bdgnbrws.com",
        "https://fvevfbr.com",
        "https://swgsdfew.com",
        "https://hodpj.cc"
    ]

    static func fallbackCandidates(preferred: String) -> [String] {
        Array(candidates(preferred: preferred, discoveredServers: "").dropFirst())
    }

    static func candidates(preferred: String, discoveredServers: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            guard let origin = normalize(value), seen.insert(origin).inserted else { return }
            result.append(origin)
        }

        append(preferred)
        parseDiscovery(discoveredServers).forEach(append)
        fallbackOrigins.forEach(append)
        append("https://jianpian.com")
        append("https://jianpian25.com")
        return result
    }

    static func parseDiscovery(_ value: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for token in value.split(whereSeparator: { $0 == "," || $0.isWhitespace || $0.isNewline }) {
            guard let origin = normalize(String(token)), seen.insert(origin).inserted else { continue }
            result.append(origin)
        }
        return result
    }

    static func shouldFailover(statusCode: Int) -> Bool {
        statusCode == 404 || statusCode == 408 || statusCode == 425
            || statusCode == 429 || statusCode >= 500
    }

    static func normalize(_ value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.first == "\"" || text.first == "'" { text.removeFirst() }
        if !text.isEmpty && (text.last == "\"" || text.last == "'") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil else { return nil }
        let port = components.port.flatMap { $0 == 443 ? nil : $0 }
        return "https://\(host.lowercased())" + (port.map { ":\($0)" } ?? "")
    }
}
