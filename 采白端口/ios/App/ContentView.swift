import SwiftUI

struct ContentView: View {
    @StateObject private var vpnManager = VPNManager.shared
    @State private var isAnimating = false
    @State private var showLog = false
    @State private var tunnelLog = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("潘多拉")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(statusText)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button(action: {
                    vpnManager.toggle()
                }) {
                    ZStack {
                        Circle()
                            .stroke(statusColor, lineWidth: 4)
                            .frame(width: 160, height: 160)
                            .scaleEffect(isAnimating ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)

                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 140, height: 140)

                        if vpnManager.isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: vpnManager.isConnected ? "checkmark" : "power")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(vpnManager.isConnecting)

                Text(vpnManager.isConnected ? "已连接" : "点击连接")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                if let err = vpnManager.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer()

                VStack(spacing: 6) {
                    Text("仅代理以下域名")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))

                    ForEach(Config.proxyDomains, id: \.self) { domain in
                        Text(domain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green.opacity(0.7))
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.top, 60)
        }
        .onAppear {
            if vpnManager.isConnected {
                isAnimating = true
            }
        }
        .onChange(of: vpnManager.isConnected) { connected in
            isAnimating = connected
        }
    }

    private var statusText: String {
        if vpnManager.isConnecting {
            return "正在连接..."
        } else if vpnManager.isConnected {
            return "VPN 已激活"
        } else {
            return "未连接"
        }
    }

    private var statusColor: Color {
        if vpnManager.isConnecting {
            return .orange
        } else if vpnManager.isConnected {
            return .green
        } else {
            return .gray
        }
    }
}