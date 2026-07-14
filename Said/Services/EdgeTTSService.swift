import CommonCrypto
import Foundation
import Starscream

enum EdgeTTSError: LocalizedError {
    case emptyText
    case invalidResponse
    case noAudio
    case timedOut

    var errorDescription: String? {
        switch self {
        case .emptyText: return "参考文本为空"
        case .invalidResponse: return "Edge TTS 返回了无法解析的数据"
        case .noAudio: return "Edge TTS 没有返回音频"
        case .timedOut: return "Edge TTS 请求超时"
        }
    }
}

protocol EdgeTTSProviding {
    @discardableResult
    func synthesize(
        text: String,
        voice: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> PronounceCancellable
}

final class EdgeTTSService: EdgeTTSProviding {
    static let shared = EdgeTTSService()
    static let defaultVoice = "en-US-GuyNeural"

    private let cacheDirectory: URL

    init(fileManager: FileManager = .default) {
        cacheDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EdgeTTS/reference-audio", isDirectory: true)
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    @discardableResult
    func synthesize(
        text: String,
        voice: String = EdgeTTSService.defaultVoice,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> PronounceCancellable {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            DispatchQueue.main.async { completion(.failure(EdgeTTSError.emptyText)) }
            return PronounceCancellation()
        }

        let destination = cacheDirectory
            .appendingPathComponent("ref_\(Self.sha256("\(voice)\n\(normalized)")).mp3")
        if Self.isUsableAudioFile(destination) {
            DispatchQueue.main.async { completion(.success(destination)) }
            return PronounceCancellation()
        }
        try? FileManager.default.removeItem(at: destination)

        let operation = EdgeTTSWebSocketOperation(
            text: normalized,
            voice: voice,
            destination: destination,
            completion: completion
        )
        operation.start()
        return PronounceCancellation { operation.cancel() }
    }

    /// Used by the batch pre-generator so its progress represents network
    /// work still needed, rather than every card in a deck.
    func hasCachedAudio(
        text: String,
        voice: String = EdgeTTSService.defaultVoice
    ) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let destination = cacheDirectory
            .appendingPathComponent("ref_\(Self.sha256("\(voice)\n\(normalized)")).mp3")
        return Self.isUsableAudioFile(destination)
    }

    private static func sha256(_ value: String) -> String {
        let data = Data(value.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isUsableAudioFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 512
    }
}

final class EdgeTTSReferenceAudioProvider: PronounceReferenceAudioProviding {
    private let service: EdgeTTSProviding
    private let voice: String

    init(
        service: EdgeTTSProviding = EdgeTTSService.shared,
        voice: String = EdgeTTSService.defaultVoice
    ) {
        self.service = service
        self.voice = voice
    }

    @discardableResult
    func audio(
        for target: PronounceTarget,
        card: AnkiCardSnapshot,
        completion: @escaping (Result<PronounceAudioAttachment, Error>) -> Void
    ) -> PronounceCancellable {
        service.synthesize(text: target.referenceText, voice: voice) { result in
            completion(result.map {
                PronounceAudioAttachment(
                    kind: .reference,
                    fileURL: $0,
                    mediaName: nil
                )
            })
        }
    }
}

private final class EdgeTTSWebSocketOperation: WebSocketDelegate {
    private static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let chromiumVersion = "143.0.3650.75"
    private static let windowsEpoch: TimeInterval = 11_644_473_600

    private let text: String
    private let voice: String
    private let destination: URL
    private let completion: (Result<URL, Error>) -> Void
    private let queue = DispatchQueue(label: "com.said.edge-tts.websocket")
    private var socket: WebSocket?
    private var audio = Data()
    private var finished = false
    private var timeout: DispatchWorkItem?

    init(
        text: String,
        voice: String,
        destination: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.text = text
        self.voice = voice
        self.destination = destination
        self.completion = completion
    }

    func start() {
        queue.async {
            let connectionID = Self.identifier()
            let token = Self.gecToken()
            let urlString = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
                + "?TrustedClientToken=\(Self.trustedClientToken)"
                + "&ConnectionId=\(connectionID)"
                + "&Sec-MS-GEC=\(token)"
                + "&Sec-MS-GEC-Version=1-\(Self.chromiumVersion)"
            guard let url = URL(string: urlString) else {
                self.finish(.failure(EdgeTTSError.invalidResponse))
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue(
                "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
                forHTTPHeaderField: "Origin"
            )
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
            request.setValue("muid=\(Self.identifier().uppercased());", forHTTPHeaderField: "Cookie")

            let socket = WebSocket(request: request, compressionHandler: WSCompression())
            socket.delegate = self
            socket.callbackQueue = self.queue
            self.socket = socket
            socket.connect()

            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(.failure(EdgeTTSError.timedOut))
            }
            self.timeout = timeout
            self.queue.asyncAfter(deadline: .now() + 45, execute: timeout)
        }
    }

    func cancel() {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            self.timeout?.cancel()
            self.socket?.disconnect()
            self.socket = nil
        }
    }

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            sendRequests(using: client)
        case .text(let text):
            if text.contains("Path:turn.end") {
                guard !audio.isEmpty else {
                    finish(.failure(EdgeTTSError.noAudio))
                    return
                }
                do {
                    try audio.write(to: destination, options: .atomic)
                    finish(.success(destination))
                } catch {
                    finish(.failure(error))
                }
            }
        case .binary(let data):
            receiveBinary(data)
        case .error(let error):
            finish(.failure(error ?? EdgeTTSError.invalidResponse))
        case .disconnected:
            if !finished {
                finish(.failure(EdgeTTSError.noAudio))
            }
        case .cancelled:
            if !finished {
                finish(.failure(EdgeTTSError.noAudio))
            }
        default:
            break
        }
    }

    private func sendRequests(using webSocket: WebSocketClient) {
        let timestamp = Self.timestamp()
        let config = "X-Timestamp:\(timestamp)\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + #"{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"true","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}"#
            + "\r\n"
        webSocket.write(string: config)

        let requestID = Self.identifier()
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(Self.xmlEscape(voice))'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"
            + Self.xmlEscape(text)
            + "</prosody></voice></speak>"
        let request = "X-RequestId:\(requestID)\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(timestamp)Z\r\n"
            + "Path:ssml\r\n\r\n"
            + ssml
        webSocket.write(string: request)
    }

    private func receiveBinary(_ value: Data) {
        guard value.count >= 2 else { return }
        let headerLength = Int(value[value.startIndex]) << 8
            | Int(value[value.index(after: value.startIndex)])
        let payloadStart = headerLength + 2
        guard payloadStart <= value.count else { return }
        let headerEnd = min(payloadStart, value.count)
        let header = String(
            data: value.subdata(in: 2..<headerEnd),
            encoding: .utf8
        ) ?? ""
        guard header.contains("Path:audio") else { return }
        if payloadStart < value.count {
            audio.append(value.suffix(from: payloadStart))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        socket?.disconnect()
        socket = nil
        DispatchQueue.main.async { self.completion(result) }
    }

    private static var userAgent: String {
        let major = chromiumVersion.split(separator: ".").first ?? "143"
        return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/\(major).0.0.0 Safari/537.36 Edg/\(major).0.0.0"
    }

    private static func identifier() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func gecToken() -> String {
        var seconds = Date().timeIntervalSince1970 + windowsEpoch
        seconds -= seconds.truncatingRemainder(dividingBy: 300)
        let ticks = UInt64(seconds * 10_000_000)
        let value = "\(ticks)\(trustedClientToken)"
        let data = Data(value.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: Date())
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
