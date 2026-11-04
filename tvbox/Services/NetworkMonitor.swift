import Foundation
import Network
import Combine

/// 网络连接状态监控器，基于 NWPathMonitor 实时跟踪设备网络可达性。
/// 供 UI 层展示离线提示、以及在网络恢复时触发自动重试。
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    /// 当前是否有可用网络连接。
    @Published private(set) var isConnected: Bool = true
    /// 当前连接类型描述（Wi-Fi / 蜂窝 / 有线 / 未知）。
    @Published private(set) var connectionType: ConnectionType = .unknown
    
    /// 网络从断开恢复到连接时发送信号，用于触发自动重试。
    let networkRestoredPublisher = PassthroughSubject<Void, Never>()
    
    enum ConnectionType: String {
        case wifi = "Wi-Fi"
        case cellular = "蜂窝"
        case wiredEthernet = "有线"
        case unknown = "未知"
    }
    
    private var monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.tvbox.networkmonitor", qos: .utility)
    private var wasDisconnected = false
    private var lastConnectedType: ConnectionType = .unknown
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connected = path.status == .satisfied
                let previouslyConnected = self.isConnected
                
                self.isConnected = connected
                self.connectionType = Self.resolveConnectionType(path)
                
                let connectionTypeChanged = connected && self.lastConnectedType != .unknown
                    && self.lastConnectedType != self.connectionType
                if connected {
                    self.lastConnectedType = self.connectionType
                    if !previouslyConnected || self.wasDisconnected || connectionTypeChanged {
                        self.wasDisconnected = false
                        self.networkRestoredPublisher.send()
                    }
                } else {
                    self.wasDisconnected = true
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// 重新创建路径监视器。应用从后台回到前台或系统切换 Wi-Fi/蜂窝网络
    /// 时调用，确保旧的 NWPath 状态不会阻塞后续恢复信号。
    func restartMonitoring() {
        monitor.cancel()
        monitor = NWPathMonitor()
        wasDisconnected = false
        lastConnectedType = .unknown
        startMonitoring()
    }
    
    private static func resolveConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return .unknown
    }
    
    deinit {
        monitor.cancel()
    }
}
