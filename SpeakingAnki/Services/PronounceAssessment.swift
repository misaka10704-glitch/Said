import Foundation

protocol PronounceCancellable: AnyObject {
    func cancel()
}

final class PronounceCancellation: PronounceCancellable {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?
    private(set) var isCancelled = false

    init(_ cancellation: (() -> Void)? = nil) {
        self.cancellation = cancellation
    }

    func install(_ action: @escaping () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            action()
        } else {
            cancellation = action
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else { lock.unlock(); return }
        isCancelled = true
        let action = cancellation
        cancellation = nil
        lock.unlock()
        action?()
    }
}

protocol PronounceAssessmentProviding {
    @discardableResult
    func assess(
        recordingURL: URL,
        target: PronounceTarget,
        completion: @escaping (Result<PronounceScoreViewModel, Error>) -> Void
    ) -> PronounceCancellable
}

enum PronounceAssessmentError: Error, LocalizedError {
    case missingCredentials
    case invalidRegion
    case unreadableRecording
    case invalidResponse(String)
    case http(Int, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "请先配置 Azure Speech Key 与 Region"
        case .invalidRegion: return "Azure Region 格式无效"
        case .unreadableRecording: return "无法读取录音"
        case .invalidResponse(let value): return "评分响应无效：\(value)"
        case .http(let code, let body): return "Azure HTTP \(code)：\(body)"
        case .cancelled: return "评分已取消"
        }
    }
}

final class AzurePronounceAssessmentClient: PronounceAssessmentProviding {
    typealias CredentialsProvider = () -> (key: String, region: String)

    private let session: URLSession
    private let credentials: CredentialsProvider

    init(
        session: URLSession = .shared,
        credentials: @escaping CredentialsProvider = {
            (KeychainStore.get(.azureSpeechKey), KeychainStore.get(.azureSpeechRegion))
        }
    ) {
        self.session = session
        self.credentials = credentials
    }

    @discardableResult
    func assess(
        recordingURL: URL,
        target: PronounceTarget,
        completion: @escaping (Result<PronounceScoreViewModel, Error>) -> Void
    ) -> PronounceCancellable {
        let token = PronounceCancellation()
        let values = credentials()
        guard !values.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !values.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dispatch(completion, .failure(PronounceAssessmentError.missingCredentials))
            return token
        }
        let region = values.region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard region.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let url = URL(string: "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed") else {
            dispatch(completion, .failure(PronounceAssessmentError.invalidRegion))
            return token
        }
        guard let wav = try? AzureWAVAudio.load(url: recordingURL),
              let audio = wav.chunks(maximumDuration: 55).first else {
            dispatch(completion, .failure(PronounceAssessmentError.unreadableRecording))
            return token
        }

        let config: [String: Any] = [
            "ReferenceText": target.referenceText,
            "GradingSystem": "HundredMark",
            "Granularity": "Phoneme",
            "Dimension": "Comprehensive",
            "EnableMiscue": true,
            "EnableProsodyAssessment": true,
            "PhonemeAlphabet": "IPA"
        ]
        guard let configData = try? JSONSerialization.data(withJSONObject: config) else {
            dispatch(completion, .failure(PronounceAssessmentError.invalidResponse("config")))
            return token
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = target.granularity == .sentence ? 90 : 30
        request.httpBody = audio
        request.setValue("audio/wav; codecs=audio/pcm; samplerate=16000", forHTTPHeaderField: "Content-Type")
        request.setValue(values.key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configData.base64EncodedString(), forHTTPHeaderField: "Pronunciation-Assessment")

        let task = session.dataTask(with: request) { data, response, error in
            if token.isCancelled { return }
            if let error = error {
                self.dispatch(completion, .failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                self.dispatch(completion, .failure(PronounceAssessmentError.http(http.statusCode, String(body.prefix(300)))))
                return
            }
            guard let data = data else {
                self.dispatch(completion, .failure(PronounceAssessmentError.invalidResponse("empty body")))
                return
            }
            do {
                self.dispatch(completion, .success(try Self.parse(data)))
            } catch {
                self.dispatch(completion, .failure(error))
            }
        }
        token.install { task.cancel() }
        task.resume()
        return token
    }

    private func dispatch<T>(_ completion: @escaping (Result<T, Error>) -> Void, _ result: Result<T, Error>) {
        DispatchQueue.main.async { completion(result) }
    }

    private static func parse(_ data: Data) throws -> PronounceScoreViewModel {
        let response = try AzurePronunciationResponse.parse(data)
        let words: [PronounceWordViewModel] = response.words.map { value in
            let phonemes: [PronouncePhonemeViewModel] = value.phonemes.map { phoneme in
                return PronouncePhonemeViewModel(
                    symbol: PronouncePhonemeNotation.ipa(for: phoneme.symbol),
                    accuracy: phoneme.accuracy,
                    stress: phoneme.stress
                )
            }
            return PronounceWordViewModel(
                word: value.text,
                accuracy: value.accuracy,
                error: value.error,
                phonemes: phonemes,
                prosodyErrors: value.prosodyErrors.isEmpty ? nil : value.prosodyErrors,
                breakLength: value.breakLength
            )
        }
        return PronounceScoreViewModel(
            transcript: response.transcript,
            accuracy: response.accuracy,
            fluency: response.fluency,
            completeness: response.completeness,
            prosody: response.prosody,
            words: words
        )
    }
}

struct PronounceRetryPolicy {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let multiplier: Double

    static let standard = PronounceRetryPolicy(maxAttempts: 3, initialDelay: 0.7, multiplier: 2)
}

final class RetryingPronounceAssessmentClient: PronounceAssessmentProviding {
    private let base: PronounceAssessmentProviding
    private let policy: PronounceRetryPolicy
    private let queue: DispatchQueue

    init(base: PronounceAssessmentProviding, policy: PronounceRetryPolicy = .standard) {
        self.base = base
        self.policy = policy
        self.queue = DispatchQueue(label: "pronounce.assessment.retry")
    }

    @discardableResult
    func assess(
        recordingURL: URL,
        target: PronounceTarget,
        completion: @escaping (Result<PronounceScoreViewModel, Error>) -> Void
    ) -> PronounceCancellable {
        let aggregate = PronounceCancellation()
        func run(_ attempt: Int) {
            guard !aggregate.isCancelled else { return }
            let active = base.assess(recordingURL: recordingURL, target: target) { result in
                guard !aggregate.isCancelled else { return }
                switch result {
                case .success:
                    completion(result)
                case .failure(let error):
                    guard attempt < max(1, self.policy.maxAttempts), Self.isRetryable(error) else {
                        completion(.failure(error))
                        return
                    }
                    let delay = self.policy.initialDelay * pow(self.policy.multiplier, Double(attempt - 1))
                    let work = DispatchWorkItem { run(attempt + 1) }
                    aggregate.install { work.cancel() }
                    self.queue.asyncAfter(deadline: .now() + delay, execute: work)
                }
            }
            aggregate.install { active.cancel() }
        }
        run(1)
        return aggregate
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let value = error as? PronounceAssessmentError {
            switch value {
            case .http(let code, _): return code == 408 || code == 429 || code >= 500
            case .invalidResponse: return true
            default: return false
            }
        }
        let code = (error as NSError).code
        return code == NSURLErrorTimedOut || code == NSURLErrorNetworkConnectionLost
            || code == NSURLErrorNotConnectedToInternet
    }
}
