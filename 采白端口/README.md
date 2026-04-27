# 采白端口 VPN

SOCKS5 分流代理 iOS 应用，仅代理 `nj.cschannel.anticheatexpert.com` 和 `4399.com`，其余流量直连。

## 代理配置

- SOCKS5 服务器：`121.204.251.76`
- 端口：`1081`
- 用户名/密码：`cb`

## 项目结构

```
ios/
├── App/                  # 主应用（SwiftUI）
├── PacketTunnel/         # Network Extension
└── Shared/Config.swift   # 共享配置
```

## 环境要求

- Xcode 15+
- iOS 15.0+
- Apple Developer 账号（含 Network Extension entitlement）

## 构建步骤

### 1. 安装 XcodeGen

```bash
brew install xcodegen
```

### 2. 生成 Xcode 项目

```bash
cd ios
xcodegen generate
```

### 3. 配置签名

在 Xcode 中选择 CaiBaiVPN target，设置你的 Development Team。PacketTunnelExtension target 也需要相同配置。

### 4. 构建

```bash
# 在 Xcode 中打开 ios/CaiBaiVPN.xcodeproj
# 选择目标设备并点击 Run
```

## GitHub 打包

请提供你的 GitHub 仓库信息，我将配置 GitHub Actions 自动构建 IPA。

## 使用说明

1. 打开 App，点击中央圆形按钮连接 VPN
2. 连接成功后，仅 `nj.cschannel.anticheatexpert.com` 和 `4399.com` 走代理
3. 其他所有流量直连本地网络