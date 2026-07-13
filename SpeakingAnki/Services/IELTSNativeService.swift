import Foundation

/// Native, callback-based IELTS pipeline for iOS 12.
/// It intentionally wraps the existing Azure REST service and reads credentials only through KeychainStore.
final class IELTSNativeService {
    typealias Completion = (IELTSServiceResult) -> Void
    typealias Progress = (IELTSStageReport) -> Void

    private let maximumAttempts: Int
    private let initialRetryDelay: TimeInterval

    init(maximumAttempts: Int = 3, initialRetryDelay: TimeInterval = 0.75) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialRetryDelay = initialRetryDelay
    }

    @discardableResult
    func score(
        _ request: IELTSServiceRequest,
        progress: Progress? = nil,
        completion: @escaping Completion
    ) -> IELTSServiceTask {
        let task = IELTSServiceTask()
        let started = Date()
        var result = IELTSServiceResult(request: request)

        guard !request.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.stages[.transcription] = failed(.transcription, "examiner question is empty")
            finish(result, started: started, completion: completion)
            return task
        }
        if let duration = request.duration,
           duration > request.part.limits.maximumRecordingSeconds {
            result.stages[.transcription] = failed(
                .transcription,
                "recording exceeds \(Int(request.part.limits.maximumRecordingSeconds)) second \(request.part.displayName) limit"
            )
            finish(result, started: started, completion: completion)
            return task
        }

        runTranscription(request, task: task, report: { report in
            result.stages[.transcription] = report
            progress?(report)
        }) { [weak self] value in
            guard let self = self else { return }
            switch value {
            case .failure:
                self.cancelRemaining(&result)
                self.finish(result, started: started, completion: completion)
            case .success(let transcript):
                result.rawTranscript = transcript
                self.runParallelAnalysis(
                    request, result: result, task: task, progress: progress
                ) { output in
                    self.finish(output, started: started, completion: completion)
                }
            }
        }
        return task
    }

    /// Retries one failed/partial stage while preserving all successful prior output.
    @discardableResult
    func retry(
        stage: IELTSStage,
        previous: IELTSServiceResult,
        progress: Progress? = nil,
        completion: @escaping Completion
    ) -> IELTSServiceTask {
        if stage == .transcription {
            return score(previous.request, progress: progress, completion: completion)
        }

        let task = IELTSServiceTask()
        let started = Date()
        var result = previous
        guard !result.rawTranscript.isEmpty else {
            result.stages[stage] = failed(stage, "transcription is required before \(stage.rawValue)")
            finish(result, started: started, completion: completion)
            return task
        }

        switch stage {
        case .transcriptRepair:
            runRepair(previous.request, raw: result.rawTranscript, task: task, report: {
                result.stages[.transcriptRepair] = $0
                progress?($0)
            }) { [weak self] value in
                guard let self = self else { return }
                if case .success(let repair) = value { result.repairedTranscript = repair }
                self.finish(result, started: started, completion: completion)
            }
        case .pronunciation:
            let reference = result.repairedTranscript.isEmpty ? result.rawTranscript : result.repairedTranscript
            runPronunciation(previous.request, reference: reference, task: task, report: {
                result.stages[.pronunciation] = $0
                progress?($0)
            }) { [weak self] value in
                guard let self = self else { return }
                if case .success(let pronunciation) = value { result.pronunciation = pronunciation }
                self.finish(result, started: started, completion: completion)
            }
        case .feedback:
            runFeedback(previous.request, result: result, task: task, report: {
                result.stages[.feedback] = $0
                progress?($0)
            }) { [weak self] value in
                guard let self = self else { return }
                if case .success(let feedback) = value { result.feedback = feedback }
                self.finish(result, started: started, completion: completion)
            }
        case .transcription:
            break
        }
        return task
    }

    private func runParallelAnalysis(
        _ request: IELTSServiceRequest,
        result initial: IELTSServiceResult,
        task: IELTSServiceTask,
        progress: Progress?,
        completion: @escaping Completion
    ) {
        var result = initial
        let group = DispatchGroup()

        group.enter()
        runRepair(request, raw: result.rawTranscript, task: task, report: {
            result.stages[.transcriptRepair] = $0
            progress?($0)
        }) { value in
            if case .success(let repair) = value { result.repairedTranscript = repair }
            group.leave()
        }

        group.enter()
        runPronunciation(request, reference: result.rawTranscript, task: task, report: {
            result.stages[.pronunciation] = $0
            progress?($0)
        }) { value in
            if case .success(let pronunciation) = value { result.pronunciation = pronunciation }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if task.isCancelled {
                self.cancelRemaining(&result)
                completion(result)
                return
            }
            let repair = result.repairedTranscript
            if !repair.isEmpty,
               IELTSTranscriptPolicy.needsReassessment(raw: result.rawTranscript, repaired: repair) {
                self.runPronunciation(request, reference: repair, task: task, report: {
                    result.stages[.pronunciation] = $0
                    progress?($0)
                }) { value in
                    if case .success(let pronunciation) = value, !pronunciation.words.isEmpty {
                        result.pronunciation = pronunciation
                    }
                    self.finishWithFeedback(request, result: result, task: task, progress: progress, completion: completion)
                }
            } else {
                self.finishWithFeedback(request, result: result, task: task, progress: progress, completion: completion)
            }
        }
    }

    private func finishWithFeedback(
        _ request: IELTSServiceRequest,
        result initial: IELTSServiceResult,
        task: IELTSServiceTask,
        progress: Progress?,
        completion: @escaping Completion
    ) {
        var result = initial
        runFeedback(request, result: result, task: task, report: {
            result.stages[.feedback] = $0
            progress?($0)
        }) { value in
            if case .success(let feedback) = value { result.feedback = feedback }
            completion(result)
        }
    }

    private func runTranscription(
        _ request: IELTSServiceRequest,
        task: IELTSServiceTask,
        report: @escaping (IELTSStageReport) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        retry(stage: .transcription, task: task, report: report, operation: { done in
            AzureSpeechService.transcribe(wavURL: request.audioURL, completion: done)
        }, completion: completion)
    }

    private func runRepair(
        _ request: IELTSServiceRequest,
        raw: String,
        task: IELTSServiceTask,
        report: @escaping (IELTSStageReport) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let hint = IELTSTranscriptPolicy.heuristicRepair(raw, question: request.question)
        if task.isCancelled {
            completion(.failure(ServiceFailure.cancelled))
            return
        }
        retry(stage: .transcriptRepair, task: task, report: report, operation: { [weak self] done in
            self?.qwen(prompt: self?.repairPrompt(question: request.question, raw: raw) ?? "", temperature: 0.1, task: task, completion: done)
        }) { value in
            switch value {
            case .success(let text):
                let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t\"'"))
                let candidate = IELTSTranscriptPolicy.heuristicRepair(cleaned, question: request.question)
                completion(.success(IELTSTranscriptPolicy.trustedRepair(raw: raw, candidate: candidate, question: request.question)))
            case .failure(let error):
                let fallback = IELTSTranscriptPolicy.isQuestionEcho(hint, question: request.question) ? "" :
                    IELTSTranscriptPolicy.trustedRepair(raw: raw, candidate: hint, question: request.question)
                if !fallback.isEmpty { completion(.success(fallback)) } else { completion(.failure(error)) }
            }
        }
    }

    private func runPronunciation(
        _ request: IELTSServiceRequest,
        reference: String,
        task: IELTSServiceTask,
        report: @escaping (IELTSStageReport) -> Void,
        completion: @escaping (Result<IELTSPronunciationResult, Error>) -> Void
    ) {
        retry(stage: .pronunciation, task: task, report: report, operation: { done in
            AzureSpeechService.scorePronunciation(wavURL: request.audioURL, referenceText: reference) { score in
                if let error = score.error, score.words.isEmpty {
                    done(.failure(ServiceFailure.message(error)))
                } else {
                    done(.success(IELTSPronunciationResult(score: score)))
                }
            }
        }, completion: completion)
    }

    private func runFeedback(
        _ request: IELTSServiceRequest,
        result: IELTSServiceResult,
        task: IELTSServiceTask,
        report: @escaping (IELTSStageReport) -> Void,
        completion: @escaping (Result<IELTSFeedback, Error>) -> Void
    ) {
        let prompt = feedbackPrompt(request: request, result: result)
        retry(stage: .feedback, task: task, report: report, operation: { [weak self] done in
            self?.qwen(prompt: prompt, temperature: 0.4, task: task, completion: done)
        }) { value in
            switch value {
            case .success(let text):
                let parsed = self.parseFeedback(text)
                if parsed.modelAnswer.isEmpty && parsed.critique.isEmpty && parsed.minimalCorrection.isEmpty {
                    completion(.failure(ServiceFailure.message("Qwen response did not contain Model/Fix/Corrected lines")))
                } else {
                    completion(.success(parsed))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func retry<T>(
        stage: IELTSStage,
        task: IELTSServiceTask,
        report: @escaping (IELTSStageReport) -> Void,
        operation: @escaping (@escaping (Result<T, Error>) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        let started = Date()
        func attempt(_ number: Int) {
            if task.isCancelled {
                var value = IELTSStageReport(stage, state: .cancelled)
                value.attempts = max(0, number - 1)
                value.elapsed = Date().timeIntervalSince(started)
                report(value)
                completion(.failure(ServiceFailure.cancelled))
                return
            }
            var running = IELTSStageReport(stage, state: .running)
            running.attempts = number
            running.elapsed = Date().timeIntervalSince(started)
            report(running)
            operation { value in
                DispatchQueue.main.async {
                    switch value {
                    case .success:
                        var success = IELTSStageReport(stage, state: .succeeded)
                        success.attempts = number
                        success.elapsed = Date().timeIntervalSince(started)
                        report(success)
                        completion(value)
                    case .failure(let error):
                        if number < self.maximumAttempts && self.isRetryable(error) && !task.isCancelled {
                            let delay = self.initialRetryDelay * pow(2, Double(number - 1))
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { attempt(number + 1) }
                        } else {
                            var failure = IELTSStageReport(stage, state: task.isCancelled ? .cancelled : .failed)
                            failure.attempts = number
                            failure.elapsed = Date().timeIntervalSince(started)
                            failure.error = error.localizedDescription
                            report(failure)
                            completion(value)
                        }
                    }
                }
            }
        }
        attempt(1)
    }

    private func qwen(
        prompt: String,
        temperature: Double,
        task owner: IELTSServiceTask,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let key = KeychainStore.get(.dashscopeKey)
        let base = KeychainStore.get(.dashscopeBase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !key.isEmpty else {
            completion(.failure(ServiceFailure.message("请先在设置中填写 DashScope API Key")))
            return
        }
        guard let url = URL(string: base + "/chat/completions") else {
            completion(.failure(ServiceFailure.message("invalid DashScope base URL")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "qwen-plus",
            "temperature": temperature,
            "messages": [["role": "user", "content": prompt]]
        ])
        let dataTask = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                completion(.failure(ServiceFailure.message("Qwen HTTP \(http.statusCode): \(body.prefix(300))")))
                return
            }
            do {
                guard let data = data,
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = root["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    throw ServiceFailure.message("无法解析 Qwen 响应")
                }
                completion(.success(content))
            } catch {
                completion(.failure(error))
            }
        }
        owner.register(dataTask)
        dataTask.resume()
    }

    private func repairPrompt(question: String, raw: String) -> String {
        """
        Examiner question (NOT the student's answer): \(question)
        Azure STT of student's speech: \(raw)

        Fix only obvious sound-alike STT errors in what the student SAID.
        NEVER replace the student's words with words from the examiner question.
        NEVER output the examiner question as the answer.
        If the student said a valid English word (even if off-topic), keep it.
        If the STT is nonsense or unrelated, return it UNCHANGED.
        Output ONLY the repaired student speech, nothing else.
        """
    }

    private func feedbackPrompt(request: IELTSServiceRequest, result: IELTSServiceResult) -> String {
        let pron = pronunciationHints(result.pronunciation)
        let nonsense = IELTSTranscriptPolicy.isQuestionEcho(result.rawTranscript, question: request.question)
        let lowAccuracy = (result.pronunciation?.accuracy ?? 100) < 40
        let sentenceRange = request.part.limits.modelSentences
        let transcript = limitedTranscript(result.rawTranscript, maximumWords: request.part.limits.maximumTranscriptWords)
        return """
        你是雅思口语 \(request.part.displayName) 教练（目标 Band 6–7）。

        考官问题：\(request.question)
        学生录音转写（Azure，可能很差）：\(transcript)
        \(pron)

        请分三步思考，但只输出下面三行：
        1) Model：你先正面回答这个问题，写 \(sentenceRange.lowerBound)–\(sentenceRange.upperBound) 句自然口语英文（示范答，直接答题）。
        2) Fix：用中文简短对比「学生转写 vs 问题」，指出问题（未答题/胡言乱语/语法/跑题/太短/发音差等），1–2 句。\(nonsense || lowAccuracy ? "学生转写明显不是正常回答，必须指出。" : "")
        3) Corrected：用英文最小化矫正「学生想说的那句话」——保留能辨认的原意；若整段无法理解，写一句可模仿的短答（勿与 Model 逐字相同）。

        严格三行，格式：
        Model: ...
        Fix: ...
        Corrected: ...
        """
    }

    private func pronunciationHints(_ value: IELTSPronunciationResult?) -> String {
        guard let value = value else { return "" }
        var lines = ["Azure pronunciation — accuracy \(value.accuracy), fluency \(value.fluency), completeness \(value.completeness)"]
        let weak = value.words.filter {
            $0.accuracy < 75
                || $0.error.map { ["Mispronunciation", "Omission", "Insertion"].contains($0) } == true
        }.prefix(15).map {
            "\($0.word)(\($0.accuracy)\($0.error.map { "," + $0 } ?? ""))"
        }
        if !weak.isEmpty { lines.append("Problem words: " + weak.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    private func parseFeedback(_ text: String) -> IELTSFeedback {
        var output = IELTSFeedback()
        text.components(separatedBy: .newlines).forEach { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("model:") {
                output.modelAnswer = String(line.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            } else if lower.hasPrefix("fix:") {
                output.critique = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("corrected:") {
                output.minimalCorrection = String(line.dropFirst(10)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        return output
    }

    private func limitedTranscript(_ text: String, maximumWords: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > maximumWords else { return text }
        return words.prefix(maximumWords).joined(separator: " ")
    }

    private func isRetryable(_ error: Error) -> Bool {
        let value = error.localizedDescription.lowercased()
        if value.contains("key") || value.contains("question is empty") || value.contains("invalid") { return false }
        if let urlError = error as? URLError,
           [.cancelled, .badURL, .unsupportedURL, .userAuthenticationRequired].contains(urlError.code) {
            return false
        }
        return true
    }

    private func failed(_ stage: IELTSStage, _ message: String) -> IELTSStageReport {
        var value = IELTSStageReport(stage, state: .failed)
        value.error = message
        return value
    }

    private func cancelRemaining(_ result: inout IELTSServiceResult) {
        for stage in IELTSStage.allCases where result.stages[stage]?.state == .pending {
            result.stages[stage] = IELTSStageReport(stage, state: .skipped)
        }
    }

    private func finish(_ value: IELTSServiceResult, started: Date, completion: @escaping Completion) {
        var result = value
        result.totalElapsed = Date().timeIntervalSince(started)
        DispatchQueue.main.async { completion(result) }
    }
}

private enum ServiceFailure: Error, LocalizedError {
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "cancelled"
        case .message(let value): return value
        }
    }
}
