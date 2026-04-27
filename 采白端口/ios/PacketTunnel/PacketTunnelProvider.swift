import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var socks5Client: SOCKS5Client?
    private let proxyDomains = Config.proxyDomains

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")

        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])

        let defaultRoute = NEIPv4Route.default()
        ipv4Settings.includedRoutes = [defaultRoute]

        let localNetworks: [String] = [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
            "127.0.0.0/8",
            "169.254.0.0/16"
        ]
        ipv4Settings.excludedRoutes = localNetworks.compactMap { cidr -> NEIPv4Route? in
            let components = cidr.split(separator: "/")
            guard components.count == 2,
                  let prefix = Int(components[1]) else { return nil }
            let mask = prefixToMask(prefix)
            let route = NEIPv4Route(destinationAddress: String(components[0]), subnetMask: mask)
            return route
        }

        settings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings

        settings.mtu = 1400

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }

            self?.startSOCKS5Tunnel(completionHandler: completionHandler)
        }
    }

    private func prefixToMask(_ prefix: Int) -> String {
        let mask = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        let b1 = (mask >> 24) & 0xFF
        let b2 = (mask >> 16) & 0xFF
        let b3 = (mask >> 8) & 0xFF
        let b4 = mask & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }

    private func startSOCKS5Tunnel(completionHandler: @escaping (Error?) -> Void) {
        socks5Client = SOCKS5Client(
            host: Config.socks5Host,
            port: Config.socks5Port,
            username: Config.socks5Username,
            password: Config.socks5Password
        )

        socks5Client?.connect { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }

            self?.startReadingPackets()
            completionHandler(nil)
        }
    }

    private func startReadingPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            self?.handlePackets(packets, protocols: protocols)
            self?.startReadingPackets()
        }
    }

    private func handlePackets(_ packets: [Data], protocols: [NSNumber]) {
        guard let client = socks5Client, client.isConnected else { return }

        for (index, packet) in packets.enumerated() {
            let proto = protocols[index].int32Value
            client.sendPacket(packet, proto: proto)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        socks5Client?.disconnect()
        socks5Client = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }
}
