import Foundation

/// Normalized Azure REST pronunciation response.
///
/// Azure's REST endpoint returns assessment values directly on NBest/Words/Phonemes,
/// while some API versions and fixtures use a nested PronunciationAssessment object.
/// Keep both shapes here so missing fields never silently become real zero scores.
struct AzurePronunciationResponse {
    struct Phoneme {
        let symbol: String
        let accuracy: Double
        let stress: Int
    }

    struct Word {
        let text: String
        let accuracy: Double
        let error: String?
        let phonemes: [Phoneme]
        let prosodyErrors: [String]
        let breakLength: Double?
    }

    let transcript: String
    let accuracy: Double
    let fluency: Double
    let completeness: Double
    let prosody: Double?
    let words: [Word]

    static func parse(_ data: Data) throws -> AzurePronunciationResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PronounceAssessmentError.invalidResponse("JSON")
        }
        let status = root["RecognitionStatus"] as? String
        guard status == nil || status == "Success" else {
            throw PronounceAssessmentError.invalidResponse(status ?? "recognition failed")
        }

        let best = (root["NBest"] as? [[String: Any]])?.first ?? root
        let nested = best["PronunciationAssessment"] as? [String: Any]
        guard let accuracy = value(best["AccuracyScore"], nested?["AccuracyScore"]),
              let fluency = value(best["FluencyScore"], nested?["FluencyScore"]),
              let completeness = value(best["CompletenessScore"], nested?["CompletenessScore"]) else {
            let body = String(data: data, encoding: .utf8) ?? "missing assessment fields"
            throw PronounceAssessmentError.invalidResponse(String(body.prefix(300)))
        }

        let words = (best["Words"] as? [[String: Any]] ?? []).map { item -> Word in
            let assessment = item["PronunciationAssessment"] as? [String: Any]
            let phonemes = (item["Phonemes"] as? [[String: Any]] ?? []).map { item -> Phoneme in
                let assessment = item["PronunciationAssessment"] as? [String: Any]
                return Phoneme(
                    symbol: item["Phoneme"] as? String ?? "",
                    accuracy: value(item["AccuracyScore"], assessment?["AccuracyScore"]) ?? 0,
                    stress: (item["Stress"] as? NSNumber)?.intValue ?? 0
                )
            }
            let error = (item["ErrorType"] as? String) ?? (assessment?["ErrorType"] as? String)
            let prosody = prosodyFeedback(item, assessment)
            return Word(
                text: item["Word"] as? String ?? "",
                accuracy: value(item["AccuracyScore"], assessment?["AccuracyScore"]) ?? 0,
                error: error == nil || error == "None" ? nil : error,
                phonemes: phonemes,
                prosodyErrors: prosody.errors,
                breakLength: prosody.breakLength
            )
        }

        return AzurePronunciationResponse(
            transcript: best["Display"] as? String ?? root["DisplayText"] as? String ?? "",
            accuracy: accuracy,
            fluency: fluency,
            completeness: completeness,
            prosody: value(best["ProsodyScore"], nested?["ProsodyScore"]),
            words: words
        )
    }

    private static func value(_ preferred: Any?, _ fallback: Any?) -> Double? {
        number(preferred) ?? number(fallback)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func prosodyFeedback(
        _ word: [String: Any],
        _ assessment: [String: Any]?
    ) -> (errors: [String], breakLength: Double?) {
        let feedback = (word["Feedback"] as? [String: Any])
            ?? (assessment?["Feedback"] as? [String: Any])
        let prosody = feedback?["Prosody"] as? [String: Any]
        let breakFeedback = prosody?["Break"] as? [String: Any]
        let intonation = prosody?["Intonation"] as? [String: Any]

        var errors: [String] = []
        [prosody, breakFeedback, intonation].compactMap { $0 }.forEach { value in
            if let values = value["ErrorTypes"] as? [String] {
                errors.append(contentsOf: values.filter { isRealProsodyError($0) })
            }
            if let value = value["ErrorType"] as? String, isRealProsodyError(value) {
                errors.append(value)
            }
        }
        return (
            Array(Set(errors)).sorted(),
            number(breakFeedback?["BreakLength"])
        )
    }

    private static func isRealProsodyError(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "none"
    }
}

/// Validates and segments the exact PCM WAV format sent to Azure.
struct AzureWAVAudio {
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let pcm: Data

    var bytesPerSecond: Int {
        sampleRate * channels * bitsPerSample / 8
    }

    var duration: TimeInterval {
        guard bytesPerSecond > 0 else { return 0 }
        return TimeInterval(pcm.count) / TimeInterval(bytesPerSecond)
    }

    static func load(url: URL) throws -> AzureWAVAudio {
        guard let data = try? Data(contentsOf: url), data.count >= 44 else {
            throw PronounceAssessmentError.unreadableRecording
        }
        guard ascii(data, 0, 4) == "RIFF", ascii(data, 8, 4) == "WAVE" else {
            throw PronounceAssessmentError.invalidResponse("录音不是 WAV 文件")
        }

        var cursor = 12
        var format: (code: Int, channels: Int, rate: Int, bits: Int)?
        var pcm: Data?
        while cursor + 8 <= data.count {
            let name = ascii(data, cursor, 4)
            let length = int32(data, cursor + 4)
            let start = cursor + 8
            guard length >= 0, start + length <= data.count else { break }
            if name == "fmt ", length >= 16 {
                format = (
                    int16(data, start),
                    int16(data, start + 2),
                    int32(data, start + 4),
                    int16(data, start + 14)
                )
            } else if name == "data" {
                pcm = data.subdata(in: start..<(start + length))
            }
            cursor = start + length + (length % 2)
        }

        guard let value = format, let pcmData = pcm, !pcmData.isEmpty,
              value.code == 1, value.channels == 1, value.rate == 16_000, value.bits == 16 else {
            throw PronounceAssessmentError.invalidResponse("录音必须是 16 kHz、单声道、16-bit PCM WAV")
        }
        return AzureWAVAudio(
            sampleRate: value.rate,
            channels: value.channels,
            bitsPerSample: value.bits,
            pcm: pcmData
        )
    }

    func chunks(maximumDuration: TimeInterval = 45) -> [Data] {
        let frameSize = max(1, channels * bitsPerSample / 8)
        let target = max(frameSize, Int(maximumDuration * Double(bytesPerSecond)) / frameSize * frameSize)
        guard pcm.count > target else { return [wavData(pcm)] }
        var output: [Data] = []
        var offset = 0
        while offset < pcm.count {
            let end = min(pcm.count, offset + target)
            output.append(wavData(pcm.subdata(in: offset..<end)))
            offset = end
        }
        return output
    }

    private func wavData(_ payload: Data) -> Data {
        var output = Data()
        output.appendASCII("RIFF")
        output.appendLE32(36 + payload.count)
        output.appendASCII("WAVEfmt ")
        output.appendLE32(16)
        output.appendLE16(1)
        output.appendLE16(channels)
        output.appendLE32(sampleRate)
        output.appendLE32(bytesPerSecond)
        output.appendLE16(channels * bitsPerSample / 8)
        output.appendLE16(bitsPerSample)
        output.appendASCII("data")
        output.appendLE32(payload.count)
        output.append(payload)
        return output
    }

    private static func ascii(_ data: Data, _ offset: Int, _ count: Int) -> String {
        String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii) ?? ""
    }

    private static func int16(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | Int(data[offset + 1]) << 8
    }

    private static func int32(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | Int(data[offset + 1]) << 8 |
            Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii) ?? Data())
    }

    mutating func appendLE16(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE32(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
