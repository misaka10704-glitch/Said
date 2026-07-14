import Foundation

/// Azure Speech via REST — works on iOS 12 without native Speech SDK.
/// Pronunciation Assessment + short-form STT.
enum AzureSpeechService {
    enum ServiceError: Error, LocalizedError {
        case missingKey
        case badResponse(String)
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "请先在设置中填写 Azure Speech Key"
            case .badResponse(let s): return s
            case .http(let c, let s): return "Azure HTTP \(c): \(s)"
            }
        }
    }

    static func scorePronunciation(
        wavURL: URL,
        referenceText: String,
        completion: @escaping (ScoreResult) -> Void
    ) {
        let key = KeychainStore.get(.azureSpeechKey)
        let region = KeychainStore.get(.azureSpeechRegion)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !region.isEmpty else {
            completion(ScoreResult(error: ServiceError.missingKey.localizedDescription))
            return
        }
        let reference = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            completion(ScoreResult(error: "参考文本为空"))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let audio = try AzureWAVAudio.load(url: wavURL)
                let chunks = audio.chunks()
                let references = split(reference: reference, count: chunks.count)
                var parts: [ScoreResult] = []
                for (index, wav) in chunks.enumerated() {
                    parts.append(try requestPronunciation(
                        wav: wav,
                        referenceText: references[index],
                        key: key,
                        region: region,
                        continuous: chunks.count > 1
                    ))
                }
                let score = aggregate(parts)
                DispatchQueue.main.async { completion(score) }
            } catch {
                DispatchQueue.main.async {
                    completion(ScoreResult(error: error.localizedDescription))
                }
            }
        }
    }

    /// STT only (no reference) — used by Compose mode before scoring with transcript as reference.
    static func transcribe(wavURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let key = KeychainStore.get(.azureSpeechKey)
        let region = KeychainStore.get(.azureSpeechRegion)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !region.isEmpty else {
            completion(.failure(ServiceError.missingKey))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let chunks = try AzureWAVAudio.load(url: wavURL).chunks()
                let texts = try chunks.map {
                    try requestTranscription(wav: $0, key: key, region: region)
                }
                let cleaned = texts.joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?'\"-"))
                guard !cleaned.isEmpty else {
                    throw ServiceError.badResponse("Azure 未识别到语音")
                }
                DispatchQueue.main.async { completion(.success(cleaned)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func requestPronunciation(
        wav: Data,
        referenceText: String,
        key: String,
        region: String,
        continuous: Bool
    ) throws -> ScoreResult {
        let config: [String: Any] = [
            "ReferenceText": referenceText,
            "GradingSystem": "HundredMark",
            "Granularity": "Phoneme",
            "Dimension": "Comprehensive",
            "EnableMiscue": !continuous,
            "EnableProsodyAssessment": true,
            "PhonemeAlphabet": "IPA"
        ]
        let configData = try JSONSerialization.data(withJSONObject: config)
        let endpoint = "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed"
        guard let url = URL(string: endpoint) else {
            throw ServiceError.badResponse("Azure Region 格式无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = wav
        request.timeoutInterval = 120
        request.setValue("audio/wav; codecs=audio/pcm; samplerate=16000", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(configData.base64EncodedString(), forHTTPHeaderField: "Pronunciation-Assessment")
        return try parsePronunciation(data: perform(request))
    }

    private static func requestTranscription(wav: Data, key: String, region: String) throws -> String {
        let endpoint = "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=simple"
        guard let url = URL(string: endpoint) else {
            throw ServiceError.badResponse("Azure Region 格式无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = wav
        request.timeoutInterval = 90
        request.setValue("audio/wav; codecs=audio/pcm; samplerate=16000", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let data = try perform(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.badResponse("无法解析 Azure 转写响应")
        }
        let status = root["RecognitionStatus"] as? String
        guard status == nil || status == "Success" else {
            throw ServiceError.badResponse(status ?? "Azure 转写失败")
        }
        guard let text = root["DisplayText"] as? String ?? root["Text"] as? String else {
            throw ServiceError.badResponse("Azure 转写响应缺少文本")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func perform(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var output: Result<Data, Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error {
                output = .failure(error)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                output = .failure(ServiceError.http(http.statusCode, String(body.prefix(300))))
                return
            }
            guard let data = data, !data.isEmpty else {
                output = .failure(ServiceError.badResponse("Azure 返回空响应"))
                return
            }
            output = .success(data)
        }.resume()
        semaphore.wait()
        guard let result = output else {
            throw ServiceError.badResponse("Azure 请求未完成")
        }
        return try result.get()
    }

    private static func split(reference: String, count: Int) -> [String] {
        guard count > 1 else { return [reference] }
        let words = reference.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return Array(repeating: reference, count: count) }
        return (0..<count).map { index in
            let start = index * words.count / count
            let end = min(words.count, (index + 1) * words.count / count)
            return start < end ? words[start..<end].joined(separator: " ") : words.last!
        }
    }

    private static func aggregate(_ parts: [ScoreResult]) -> ScoreResult {
        guard !parts.isEmpty else { return ScoreResult(error: "Azure 未返回评分") }
        let count = Double(parts.count)
        var result = ScoreResult(
            transcript: parts.map { $0.transcript }.filter { !$0.isEmpty }.joined(separator: " "),
            accuracy: parts.reduce(0) { $0 + $1.accuracy } / count,
            fluency: parts.reduce(0) { $0 + $1.fluency } / count,
            completeness: parts.reduce(0) { $0 + $1.completeness } / count
        )
        let prosodyParts = parts.compactMap { $0.prosody }
        if !prosodyParts.isEmpty {
            result.prosody = prosodyParts.reduce(0, +) / Double(prosodyParts.count)
        }
        result.words = parts.flatMap { $0.words }
        let errors = parts.compactMap { $0.error }.filter { !$0.isEmpty }
        if !errors.isEmpty { result.error = errors.joined(separator: " | ") }
        return result
    }

    private static func parsePronunciation(data: Data) throws -> ScoreResult {
        let parsed = try AzurePronunciationResponse.parse(data)
        var result = ScoreResult(
            transcript: parsed.transcript,
            accuracy: parsed.accuracy,
            fluency: parsed.fluency,
            completeness: parsed.completeness,
            prosody: parsed.prosody
        )
        result.words = parsed.words.map { word in
            PronunciationWordScore(
                word: word.text,
                accuracy: word.accuracy,
                error: word.error,
                phonemes: word.phonemes.map {
                    PronunciationPhonemeScore(
                        symbol: PronouncePhonemeNotation.ipa(for: $0.symbol),
                        accuracy: $0.accuracy,
                        stress: $0.stress
                    )
                },
                prosodyErrors: word.prosodyErrors.isEmpty ? nil : word.prosodyErrors,
                breakLength: word.breakLength
            )
        }
        return result
    }
}
