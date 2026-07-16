import Foundation

enum TranslationError: LocalizedError {
    case missingKey
    case emptyText
    case badResponse(String)
    case http(Int, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在设置中填写 DashScope API Key"
        case .emptyText: return "待翻译文本为空"
        case .badResponse(let message): return message
        case .http(let code, let body): return "翻译 HTTP \(code): \(body)"
        case .cancelled: return "已取消"
        }
    }
}

/// English → Chinese translation via DashScope (qwen-plus).
final class TranslationService {
    static let shared = TranslationService()
    static let defaultModel = "qwen-plus"

    private init() {}

    @discardableResult
    func translate(
        text: String,
        model: String = TranslationService.defaultModel,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> PronounceCancellable {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            DispatchQueue.main.async { completion(.failure(TranslationError.emptyText)) }
            return PronounceCancellation()
        }

        let key = KeychainStore.get(.dashscopeKey)
        let base = KeychainStore.get(.dashscopeBase)
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(.failure(TranslationError.missingKey)) }
            return PronounceCancellation()
        }

        let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.badResponse("DashScope Base URL 无效")))
            }
            return PronounceCancellation()
        }

        let prompt = Self.prompt(for: normalized)
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [["role": "user", "content": prompt]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var dataTask: URLSessionDataTask?
        dataTask = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error as NSError?, error.code == NSURLErrorCancelled {
                DispatchQueue.main.async { completion(.failure(TranslationError.cancelled)) }
                return
            }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(TranslationError.http(http.statusCode, String(text.prefix(300)))))
                }
                return
            }
            guard
                let data = data,
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = root["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                DispatchQueue.main.async {
                    completion(.failure(TranslationError.badResponse("无法解析翻译响应")))
                }
                return
            }
            let translation = Self.normalizeTranslation(content)
            guard !translation.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(TranslationError.badResponse("翻译结果为空")))
                }
                return
            }
            DispatchQueue.main.async { completion(.success(translation)) }
        }
        dataTask?.resume()
        return PronounceCancellation { dataTask?.cancel() }
    }

    private static func prompt(for text: String) -> String {
        if looksLikeLexicalEntry(text) {
            return """
            将下列英文单词或短语翻译为中文，列出 2–4 个常见义项或用法，用中文分号「；」分隔。
            只输出义项列表，不要词性标注、不要例句、不要解释、不要编号。

            \(text)
            """
        }
        return """
        将下列英文翻译为自然、简洁的中文。只输出译文，不要解释、不要引号、不要编号。

        \(text)
        """
    }

    private static func looksLikeLexicalEntry(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count <= 4 else { return false }
        return trimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil
            && trimmed.range(of: "[0-9]", options: .regularExpression) == nil
    }

    private static func normalizeTranslation(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[\"'「」]+|[\"'「」]+$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n", with: "；")
        text = text.replacingOccurrences(of: ";", with: "；")
        text = text.replacingOccurrences(of: "，", with: "；")
        text = text.replacingOccurrences(of: "、", with: "；")
        text = text.replacingOccurrences(of: "\\s*；\\s*", with: "；", options: .regularExpression)
        text = text.replacingOccurrences(of: "；+", with: "；", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "；"))
    }
}
