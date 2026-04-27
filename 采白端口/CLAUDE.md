# 采白端口 — SOCKS5 Split-Tunnel VPN

## 项目概述

- **类型**：iOS VPN 应用（SOCKS5 分流代理）
- **核心功能**：点击连接按钮激活 SOCKS5 VPN，仅代理 `nj.cschannel.anticheatexpert.com` 和 `4399.com` 两个域名，其余流量走本地直连
- **目标平台**：iOS

## 代理配置（硬编码，不可暴露）

- SOCKS5 服务器：`121.204.251.76`
- 端口：`1081`
- 用户名：`cb`
- 密码：`cb`
- 分流规则：仅代理 `nj.cschannel.anticheatexpert.com` 和 `4399.com`，其余流量本地直连

## 技术架构

```
iOS App (NEVPNManager)
  └── PacketTunnelProvider (NetworkExtension)
        └── Split-Tunnel 路由
              ├── 目标域名匹配 → SOCKS5 Proxy (121.204.251.76:1081)
              └── 其他 → 直连本地网络
```

## iOS 技术栈

- **UI**：SwiftUI（主应用）
- **VPN**：NetworkExtension + NEPacketTunnelProvider
- **SOCKS5**：直接基于 GCDAsyncSocket 实现（不依赖第三方库）
- **域名解析**：系统 DNS + 路由策略

## 目录结构

```
ios/
  ├── App/                    # 主应用 Target
  │   ├── App.swift           # 入口
  │   ├── ContentView.swift   # UI：连接按钮
  │   ├── VPNManager.swift    # NEVPNManager 封装
  │   └── Info.plist
  ├── PacketTunnel/           # Network Extension Target
  │   ├── PacketTunnelProvider.swift
  │   ├── SOCKS5Client.swift  # SOCKS5 协议实现
  │   ├── DNSServer.swift     # 定制 DNS 解析
  │   └── Info.plist
  ├── Shared/
  │   └── Config.swift        # 共享配置（硬编码）
  └── project.yml             # XcodeGen 配置

server/                      # 可选本地 SOCKS5 测试服务器（Python）
  └── socks5_server.py
```

## 构建

- XcodeGen 生成 `.xcodeproj`
- 主应用 + PacketTunnel Extension 分别构建
- 签名需要有效的开发者证书和 Network Extension entitlement

## 注意事项

- SOCKS5 凭据硬编码在 `Shared/Config.swift`，不暴露在 UI 层
- VPN 配置通过 NEVPNManager API 保存到系统设置
- 分流逻辑：域名匹配则路由到 SOCKS5，其他直连