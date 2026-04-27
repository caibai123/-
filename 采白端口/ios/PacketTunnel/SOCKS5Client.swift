import Foundation

enum SOCKS5Error: Error {
    case connectionFailed
    case notConnected
    case writeFailed
    case authenticationFailed
    case proxyError(String)
    case timeout
}

class SOCKS5Client: NSObject {
    private let host: String
    private let port: UInt16
    private let username: String
    private let password: String

    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var completion: ((Error?) -> Void)?
    private var readBuffer = Data()
    private var handshakeStep = 0
    private var timeoutWorkItem: DispatchWorkItem?

    private(set) var isConnected = false

    init(host: String, port: UInt16, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        super.init()
    }

    func connect(completion: @escaping (Error?) -> Void) {
        self.completion = completion

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            host as CFString,
            UInt32(port),
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

        inputStream?.schedule(in: .main, forMode: .common)
        outputStream?.schedule(in: .main, forMode: .common)

        inputStream?.open()
        outputStream?.open()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isConnected else { return }
            self.cleanup()
            DispatchQueue.main.async {
                self.completion?(SOCKS5Error.timeout)
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    private func doHandshake() {
        guard let output = outputStream else {
            callCompletion(with: SOCKS5Error.notConnected)
            return
        }

        var greeting = Data([0x05, 0x01, 0x02])
        let written = greeting.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }

        if written <= 0 {
            callCompletion(with: SOCKS5Error.writeFailed)
        }
    }

    private func doAuth() {
        guard let output = outputStream else {
            callCompletion(with: SOCKS5Error.notConnected)
            return
        }

        let usernameBytes = Array(username.utf8)
        let passwordBytes = Array(password.utf8)

        var authData = Data()
        authData.append(0x01)
        authData.append(UInt8(usernameBytes.count))
        authData.append(contentsOf: usernameBytes)
        authData.append(UInt8(passwordBytes.count))
        authData.append(contentsOf: passwordBytes)

        let written = authData.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }

        if written <= 0 {
            callCompletion(with: SOCKS5Error.writeFailed)
        }
    }

    private func doConnect() {
        guard let output = outputStream else {
            callCompletion(with: SOCKS5Error.notConnected)
            return
        }

        var request = Data()
        request.append(0x05)
        request.append(0x01)
        request.append(0x00)

        request.append(0x01)
        request.append(contentsOf: [0, 0, 0, 1])

        request.append(0x00)
        request.append(0x00)

        let written = request.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }

        if written <= 0 {
            callCompletion(with: SOCKS5Error.writeFailed)
        }
    }

    private func handleStreamEvent(_ stream: Stream) {
        guard stream == inputStream || stream == outputStream else { return }

        if let error = stream.streamError {
            cleanup()
            callCompletion(with: SOCKS5Error.proxyError(error.localizedDescription))
            return
        }

        if stream == outputStream {
            let events = stream.eventCode
            if events.contains(.openCompleted) {
                if handshakeStep == 0 {
                    handshakeStep = 1
                    doHandshake()
                }
            }
        }

        if stream == inputStream {
            let events = stream.eventCode

            if events.contains(.hasBytesAvailable) {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = inputStream?.read(&buffer, maxLength: buffer.count) ?? 0

                if bytesRead > 0 {
                    readBuffer.append(contentsOf: buffer[0..<bytesRead])
                    processReadBuffer()
                } else if bytesRead < 0 {
                    cleanup()
                    callCompletion(with: SOCKS5Error.connectionFailed)
                }
            }

            if events.contains(.errorOccurred) {
                cleanup()
                callCompletion(with: SOCKS5Error.connectionFailed)
            }

            if events.contains(.endEncountered) {
                cleanup()
                callCompletion(with: SOCKS5Error.connectionFailed)
            }
        }
    }

    private func processReadBuffer() {
        guard readBuffer.count >= 2 else { return }

        let byte0 = readBuffer[0]

        if handshakeStep == 1 && byte0 == 0x05 {
            let byte1 = readBuffer[1]
            if byte1 == 0x02 {
                readBuffer.removeAll()
                handshakeStep = 2
                doAuth()
            } else if byte1 == 0x00 {
                readBuffer.removeAll()
                handshakeStep = 3
                doConnect()
            } else {
                callCompletion(with: SOCKS5Error.authenticationFailed)
            }
        } else if handshakeStep == 2 && byte0 == 0x01 {
            let byte1 = readBuffer[1]
            if byte1 == 0x00 {
                readBuffer.removeAll()
                handshakeStep = 3
                doConnect()
            } else {
                callCompletion(with: SOCKS5Error.authenticationFailed)
            }
        } else if handshakeStep == 3 && byte0 == 0x05 {
            let byte1 = readBuffer[1]
            if byte1 == 0x00 {
                isConnected = true
                timeoutWorkItem?.cancel()
                callCompletion(with: nil)
            } else {
                let errorMsg: String
                switch byte1 {
                case 0x01: errorMsg = "general SOCKS server failure"
                case 0x02: errorMsg = "connection not allowed by ruleset"
                case 0x03: errorMsg = "network unreachable"
                case 0x04: errorMsg = "host unreachable"
                case 0x05: errorMsg = "connection refused"
                case 0x06: errorMsg = "TTL expired"
                case 0x07: errorMsg = "command not supported"
                case 0x08: errorMsg = "address type not supported"
                default: errorMsg = "SOCKS error code \(byte1)"
                }
                callCompletion(with: SOCKS5Error.proxyError(errorMsg))
            }
        }
    }

    private func callCompletion(with error: Error?) {
        let cb = completion
        completion = nil
        DispatchQueue.main.async {
            cb?(error)
        }
    }

    private func cleanup() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        inputStream?.close()
        outputStream?.close()
        inputStream?.remove(from: .main, forMode: .common)
        outputStream?.remove(from: .main, forMode: .common)
        inputStream = nil
        outputStream = nil
        isConnected = false
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

        tcpData.withUnsafeMutableBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }
    }

    func disconnect() {
        cleanup()
    }
}

extension SOCKS5Client: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        handleStreamEvent(aStream)
    }
}
