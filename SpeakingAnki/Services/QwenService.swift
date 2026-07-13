import Foundation

/// DashScope OpenAI-compatible Qwen Omni audio analysis with qwen-plus text fallback.
enum QwenService {
    enum ServiceError: Error, LocalizedError {
        case missingKey
        case badResponse(String)
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "请先在设置中填写 DashScope API Key"
            case .badResponse(let s): return s
            case .http(let c, let s): return "Qwen HTTP \(c): \(s)"
            }
        }
    }

    static func fixBetter(
        audioURL: URL? = nil,
        prompt: String,
        transcript: String = "",
        completion: @escaping (Result<(fix: String, better: String), Error>) -> Void
    ) {
        let key = KeychainStore.get(.dashscopeKey)
        let base = KeychainStore.get(.dashscopeBase)
        guard !key.isEmpty else {
            completion(.failure(ServiceError.missingKey))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
                guard let url = URL(string: endpoint) else { throw ServiceError.badResponse("bad base url") }
                var omniError: Error?
                if let audioURL = audioURL, let audio = try? Data(contentsOf: audioURL), !audio.isEmpty {
                    do {
                        let dataURI = "data:audio/wav;base64,\(audio.base64EncodedString())"
                        let body: [String: Any] = [
                            "model": "qwen3-omni-flash",
                            "modalities": ["text"],
                            "stream": false,
                            "enable_thinking": false,
                            "messages": [[
                                "role": "user",
                                "content": [
                                    ["type": "input_audio", "input_audio": ["data": dataURI, "format": "wav"]],
                                    ["type": "text", "text": prompt]
                                ]
                            ]]
                        ]
                        let parsed = ComposeMode.parseFixBetter(
                            try request(url: url, key: key, body: body, timeout: 120)
                        )
                        if !parsed.fix.isEmpty || !parsed.better.isEmpty {
                            DispatchQueue.main.async { completion(.success(parsed)) }
                            return
                        }
                    } catch {
                        omniError = error
                    }
                }

                var fallbackPrompt = prompt
                if !transcript.isEmpty {
                    fallbackPrompt += "\n\nStudent said (transcript): \(transcript)"
                }
                let fallback: [String: Any] = [
                    "model": "qwen-plus",
                    "temperature": 0.4,
                    "messages": [["role": "user", "content": fallbackPrompt]]
                ]
                let parsed = ComposeMode.parseFixBetter(
                    try request(url: url, key: key, body: fallback, timeout: 90)
                )
                if parsed.fix.isEmpty && parsed.better.isEmpty, let omniError = omniError {
                    throw ServiceError.badResponse("Qwen Omni 与文本降级均无有效结果：\(omniError.localizedDescription)")
                }
                DispatchQueue.main.async { completion(.success(parsed)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func request(
        url: URL,
        key: String,
        body: [String: Any],
        timeout: TimeInterval
    ) throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        var output: Result<Data, Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error {
                output = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                output = .failure(ServiceError.http(http.statusCode, String(text.prefix(300))))
            } else if let data = data {
                output = .success(data)
            } else {
                output = .failure(ServiceError.badResponse("Qwen 返回空响应"))
            }
        }.resume()
        semaphore.wait()
        guard let data = try output?.get(),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ServiceError.badResponse("无法解析 Qwen 响应")
        }
        return content
    }
}
