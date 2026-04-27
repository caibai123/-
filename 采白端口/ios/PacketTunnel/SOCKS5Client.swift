import Foundation
import NetworkExtension

class SOCKS5Client {
    private let host: String
    private let port: UInt16
    private let username: String
    private let password: String

    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let queue = DispatchQueue(label: "com.caibai.socks5", qos: .userInitiated)

    private(set) var isConnected = false

    init(host: String, port: UInt16, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    func connect(completion: @escaping (Error?) -> Void) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            host as CFString,
            port,
            &readStream,
            &writeStream
        )

        guard let input = readStream?.takeRetainedValue(),
              let output = writeStream?.takeRetainedValue() else {
            completion(SOCKS5Error.connectionFailed)
            return
        }

        inputStream = input as InputStream
        outputStream = output as OutputStream

        inputStream?.delegate = self
        outputStream?.delegate = self

        queue.async { [weak self] in
            self?.inputStream?.schedule(in: .main, forMode: .common)
            self?.outputStream?.schedule(in: .main, forMode: .common)
            self?.inputStream?.open()
            self?.outputStream?.open()
        }

        handshake(completion: completion)
    }

    private func handshake(completion: @escaping (Error?) -> Void) {
        var greeting = Data([0x05, 0x01, 0x02])

        guard let output = outputStream else {
            completion(SOCKS5Error.notConnected)
            return
        }

        let written = greeting.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }

        guard written > 0 else {
            completion(SOCKS5Error.writeFailed)
            return
        }

        var response = [UInt8](repeating: 0, count: 2)
        let bytesRead = response.withUnsafeMutableBytes { buffer in
            inputStream?.read(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: 2) ?? 0
        }

        guard bytesRead == 2, response[0] == 0x05, response[1] == 0x02 else {
            completion(SOCKS5Error.authenticationFailed)
            return
        }

        authenticate(completion: completion)
    }

    private func authenticate(completion: @escaping (Error?) -> Void) {
        let usernameBytes = Array(username.utf8)
        let passwordBytes = Array(password.utf8)

        var authData = Data()
        authData.append(0x01)
        authData.append(UInt8(usernameBytes.count))
        authData.append(contentsOf: usernameBytes)
        authData.append(UInt8(passwordBytes.count))
        authData.append(contentsOf: passwordBytes)

        guard let output = outputStream else {
            completion(SOCKS5Error.notConnected)
            return
        }

        let written = authData.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }

        guard written > 0 else {
            completion(SOCKS5Error.writeFailed)
            return
        }

        var authResponse = [UInt8](repeating: 0, count: 2)
        let bytesRead = authResponse.withUnsafeMutableBytes { buffer in
            inputStream?.read(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: 2) ?? 0
        }

        guard bytesRead == 2, authResponse[1] == 0x00 else {
            completion(SOCKS5Error.authenticationFailed)
            return
        }

        isConnected = true
        completion(nil)
    }

    func sendPacket(_ packet: Data, proto: Int32) {
        guard isConnected, let output = outputStream else { return }

        var proxyRequest = Data()

        proxyRequest.append(0x05)
        proxyRequest.append(0x01)
        proxyRequest.append(0x00)

        if packet.count > 20 {
            let destIP = packet.subdata(in: 16..<20)
            proxyRequest.append(0x01)
            proxyRequest.append(contentsOf: destIP)

            let destPort = packet.subdata(in: 22..<24)
            proxyRequest.append(contentsOf: destPort)
        } else {
            return
        }

        var tcpData = Data()
        tcpData.append(contentsOf: proxyRequest)
        tcpData.append(contentsOf: packet)

        let _ = tcpData.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }
    }

    func disconnect() {
        isConnected = false
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
    }
}

extension SOCKS5Client: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .errorOccurred:
            isConnected = false
        case .endEncountered:
            isConnected = false
        default:
            break
        }
    }
}

enum SOCKS5Error: Error {
    case connectionFailed
    case notConnected
    case writeFailed
    case authenticationFailed
    case proxyError(String)
}
