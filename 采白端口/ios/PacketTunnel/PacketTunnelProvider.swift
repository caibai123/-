import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var socks5Client: SOCKS5Client?
    private var pendingStartCompletion: ((Error?) -> Void)?
    private let proxyDomains = Config.proxyDomains

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        pendingStartCompletion = completionHandler

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Config.socks5Host)

        let ipv4Settings = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])

        let defaultRoute = NEIPv4Route.default()
        defaultRoute.gatewayAddress = Config.socks5Host

        let proxyRoute = NEIPv4Route(destinationAddress: Config.socks5Host, subnetMask: "255.255.255.255")
        proxyRoute.gatewayAddress = Config.socks5Host

        ipv4Settings.includedRoutes = [proxyRoute]
        ipv4Settings.excludedRoutes = [defaultRoute]

        settings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8"])
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

            if let domain = extractDomainFromPacket(packet, proto: proto) {
                if shouldProxyDomain(domain) {
                    client.sendPacket(packet, proto: proto)
                }
            } else {
                client.sendPacket(packet, proto: proto)
            }
        }
    }

    private func extractDomainFromPacket(_ packet: Data, proto: Int32) -> String? {
        guard packet.count > 20 else { return nil }

        let ipHeaderLength = Int(packet[0] & 0x0F) * 4
        guard packet.count > ipHeaderLength else { return nil }

        let ipProtocol = packet[9]

        if ipProtocol == 6 {
            let tcpHeaderLength = ipHeaderLength + 20
            guard packet.count > tcpHeaderLength + 4 else { return nil }

            let destIP = String(format: "%d.%d.%d.%d",
                packet[16], packet[17], packet[18], packet[19])

            if destIP == Config.socks5Host {
                return nil
            }

            let destPort = UInt16(packet[22]) << 8 | UInt16(packet[23])

            if destPort == 80 || destPort == 443 {
                if packet.count > tcpHeaderLength + 40 {
                    let httpData = packet.subdata(in: tcpHeaderLength + 40..<min(tcpHeaderLength + 200, packet.count))
                    if let httpString = String(data: httpData, encoding: .utf8) {
                        if let hostRange = httpString.range(of: "Host: ", options: .caseInsensitive) {
                            let start = hostRange.upperBound
                            if let end = httpString[start...].firstIndex(of: "\r") {
                                return String(httpString[start..<end]).trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    private func shouldProxyDomain(_ domain: String) -> Bool {
        let lowercased = domain.lowercased()
        for proxyDomain in proxyDomains {
            if lowercased == proxyDomain.lowercased() || lowercased.hasSuffix(".\(proxyDomain)") {
                return true
            }
        }
        return false
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
