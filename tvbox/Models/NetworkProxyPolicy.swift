import Foundation

/// Controls whether app-owned URLSession requests inherit the system proxy.
///
/// The default is deliberately disabled: a device-wide proxy can be stale or
/// unreachable after relaunch and would otherwise make source and danmaku
/// requests fail together. Users can opt in from Settings.
enum NetworkProxyPolicy {
    static let useSystemProxyKey = "network_use_system_proxy"

    static var useSystemProxy: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: useSystemProxyKey) != nil else {
            defaults.set(false, forKey: useSystemProxyKey)
            return false
        }
        return defaults.bool(forKey: useSystemProxyKey)
    }

    static func setUseSystemProxy(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useSystemProxyKey)
    }

    static func configure(_ configuration: URLSessionConfiguration) {
        guard !useSystemProxy else { return }
        // CFNetwork proxy keys are intentionally supplied as literals so this
        // helper remains available to both the iOS and macOS targets. Disable
        // PAC and SOCKS as well as HTTP(S); otherwise a device-wide PAC can
        // still route requests through a proxy even when HTTPEnable is zero.
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "FTPEnable": 0,
            "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0,
            "ProxyAutoDiscoveryEnable": 0
        ]
    }
}
