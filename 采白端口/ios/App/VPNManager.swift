import Foundation
import NetworkExtension

class VPNManager: ObservableObject {
    static let shared = VPNManager()

    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var statusMessage = ""

    private var manager: NETunnelProviderManager?

    private init() {
        loadManager()
    }

    private func loadManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.statusMessage = "加载失败: \(error.localizedDescription)"
                    return
                }

                if let existing = managers?.first {
                    self?.manager = existing
                    existing.isEnabled = true
                } else {
                    self?.createManager()
                }

                self?.observeStatus()
            }
        }
    }

    private func createManager() {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "潘多拉 VPN"

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = Config.tunnelBundleIdentifier
        tunnelProtocol.serverAddress = Config.socks5Host
        tunnelProtocol.providerConfiguration = [
            "host": Config.socks5Host,
            "port": Config.socks5Port,
            "username": Config.socks5Username,
            "password": Config.socks5Password,
            "domains": Config.proxyDomains
        ] as [String: Any]

        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true

        self.manager = manager

        manager.saveToPreferences { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.statusMessage = "保存配置失败: \(error.localizedDescription)"
                }
                return
            }
            manager.loadFromPreferences { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.statusMessage = "加载配置失败: \(error.localizedDescription)"
                    } else {
                        self?.statusMessage = "准备就绪"
                    }
                }
            }
        }
    }

    private func observeStatus() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager?.connection,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }

    private func updateStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let connection = self.manager?.connection else { return }

            switch connection.status {
            case .connected:
                self.isConnected = true
                self.isConnecting = false
                self.statusMessage = "VPN 已激活"
            case .connecting:
                self.isConnected = false
                self.isConnecting = true
                self.statusMessage = "正在连接..."
            case .disconnecting:
                self.isConnecting = true
                self.statusMessage = "正在断开..."
            case .disconnected:
                self.isConnected = false
                self.isConnecting = false
                self.statusMessage = "未连接"
            case .invalid:
                self.isConnected = false
                self.isConnecting = false
                self.statusMessage = "配置无效"
            case .reasserting:
                self.isConnecting = true
            @unknown default:
                break
            }
        }
    }

    func toggle() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        guard let manager = manager else {
            createManager()
            isConnecting = true
            return
        }

        isConnecting = true
        statusMessage = "正在连接..."

        manager.saveToPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.statusMessage = "保存配置失败: \(error.localizedDescription)"
                    self?.isConnecting = false
                    return
                }

                manager.loadFromPreferences { [weak self] error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.statusMessage = "加载配置失败: \(error.localizedDescription)"
                            self?.isConnecting = false
                            return
                        }

                        do {
                            try manager.connection.startVPNTunnel()
                        } catch {
                            self?.statusMessage = "启动失败: \(error.localizedDescription)"
                            self?.isConnecting = false
                        }
                    }
                }
            }
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }
}
