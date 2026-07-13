import UIKit
import WebKit
import AVFoundation

final class ReviewViewController: UIViewController, ThemeRefreshable, WKNavigationDelegate, AVAudioPlayerDelegate {
    private let deckId: Int64
    private let deckName: String
    private let cardView = CardRevealView()
    private var webView: CardWebView { cardView.webView }
    private let statusLabel = UILabel()
    private let resultPanel = SpeakingResultPanel()
    private let controlBar = ReviewControlBar()
    private let easeBar = AnswerEaseBar()
    private lazy var undoControl: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(ActionIconFactory.image(.undo, pointSize: 16), for: .normal)
        button.setTitle(" 撤销", for: .normal)
        button.titleLabel?.font = DSTheme.titleFont(size: 13)
        button.accessibilityLabel = "撤销上一评分"
        button.addTarget(self, action: #selector(undoLastAnswer), for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 64, height: 32)
        return button
    }()
    private lazy var undoButton = UIBarButtonItem(customView: undoControl)

    private let pronounceSession = PronounceSessionController()
    private let player = AudioPlayer()
    private let edgeTTS = EdgeTTSService.shared
    private let ieltsService = IELTSNativeService()

    private var card: AnkiCardSnapshot?
    private var mode: PracticeMode = .unsupported
    private var isAnswering = false
    private var isRecording = false
    private var sessionStart = Date()
    private var operationGeneration = 0
    private var didAttachCurrentRecording = false

    private var currentWebNavigation: WKNavigation?
    private var cardMediaPlayer: AVAudioPlayer?
    private var referenceMediaQueue: [URL] = []
    private var playbackMediaQueue: [URL] = []
    private var activeMediaQueue: [URL] = []
    private var cardMediaIndex = 0
    private var cardMediaShouldContinue = false
    private var cardSpeechText = ""
    private var activeEdgeTTSTask: PronounceCancellable?
    private var activeIELTSTask: IELTSServiceTask?

    private var resultHeight: NSLayoutConstraint!
    private var webPreferredHeight: NSLayoutConstraint!
    private var easeHeight: NSLayoutConstraint!

    init(deckId: Int64, deckName: String) {
        self.deckId = deckId
        self.deckName = deckName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = deckName
        navigationItem.rightBarButtonItem = undoButton
        undoControl.isEnabled = false
        buildLayout()
        bindActions()
        webView.navigationDelegate = self
        pronounceSession.onStateChange = { [weak self] state in
            self?.renderPronounceSession(state)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .saidThemeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        pronounceSession.requestRecordingPermission { [weak self] allowed in
            if !allowed { self?.setStatus("需要麦克风权限", error: true) }
        }
        MemoryGuard.lowMemoryWarningInstall(on: self) { [weak self] in
            self?.releaseTransientResources()
            MemoryGuard.trimWebViewProcessIfNeeded()
            self?.setStatus("内存紧张：已释放音频与网络任务", error: true)
        }
        applyTheme()
        loadNext()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupReviewSession(stopWebView: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cleanupReviewSession(stopWebView: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        DSTheme.c.statusBarStyle
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let compactCardHeight: CGFloat = view.bounds.height < 700 ? 132 : (view.bounds.height < 850 ? 170 : 210)
        if webPreferredHeight.constant != compactCardHeight {
            webPreferredHeight.constant = compactCardHeight
        }
    }

    func applyTheme() {
        let colors = DSTheme.c
        view.backgroundColor = colors.background
        statusLabel.textColor = colors.textSecondary
        webView.applyTheme()
        controlBar.applyTheme()
        easeBar.applyTheme()
        resultPanel.applyTheme()
        undoControl.tintColor = colors.accent
        undoControl.setTitleColor(colors.accent, for: .normal)
        undoControl.setTitleColor(colors.textTertiary, for: .disabled)
        cardView.applyTheme()
        setNeedsStatusBarAppearanceUpdate()
        guard let card = card else { return }
        let revealed = cardView.isRevealed
        loadCardSide(reviewHTML(for: card), card: card)
        if revealed { cardView.reveal() } else { cardView.conceal() }
    }

    private func buildLayout() {
        statusLabel.font = DSTheme.bodyFont(size: 12)
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(cardView)
        view.addSubview(resultPanel)
        view.addSubview(controlBar)
        view.addSubview(easeBar)

        resultHeight = resultPanel.heightAnchor.constraint(equalToConstant: 42)
        resultHeight.priority = .required
        resultHeight.isActive = false
        easeHeight = easeBar.heightAnchor.constraint(equalToConstant: 60)
        let webMinimum = cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        webMinimum.priority = UILayoutPriority(999)
        webPreferredHeight = cardView.heightAnchor.constraint(equalToConstant: 170)
        webPreferredHeight.priority = UILayoutPriority(999)
        webPreferredHeight.isActive = true
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeTopAnchor, constant: 7),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            cardView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 7),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            webMinimum,

            resultPanel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 8),
            resultPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            resultPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            controlBar.topAnchor.constraint(equalTo: resultPanel.bottomAnchor, constant: 8),
            controlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            controlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            controlBar.heightAnchor.constraint(equalToConstant: 52),

            easeBar.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: 8),
            easeBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            easeBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            easeHeight,
            easeBar.bottomAnchor.constraint(equalTo: safeBottomAnchor, constant: -8)
        ])
        easeBar.isHidden = false
    }

    private func bindActions() {
        controlBar.onAction = { [weak self] action in
            switch action {
            case .reference: self?.playReference()
            case .record: self?.toggleRecording()
            case .playback: self?.playRecording()
            case .score: self?.runScore()
            }
        }
        easeBar.onEase = { [weak self] ease in self?.answer(ease) }
        resultPanel.onCollapseChange = { [weak self] collapsed in
            self?.setResultCollapsed(collapsed)
        }
        cardView.onReveal = { [weak self] in
            guard let self = self, self.card != nil else { return }
            self.setStatus("\(self.modeTitle(self.mode)) · 已显示原始问题 / 句子")
        }
        cardView.onConceal = { [weak self] in
            guard let self = self, let card = self.card else { return }
            self.setStatus("\(self.modeTitle(self.mode))  ·  \(card.modelName)")
        }
    }

    private var safeTopAnchor: NSLayoutYAxisAnchor {
        view.safeAreaLayoutGuide.topAnchor
    }

    private var safeBottomAnchor: NSLayoutYAxisAnchor {
        view.safeAreaLayoutGuide.bottomAnchor
    }

    private func loadNext() {
        cleanupReviewSession(stopWebView: false)
        operationGeneration += 1
        isAnswering = false
        isRecording = false
        didAttachCurrentRecording = false
        setAnswerControlsEnabled(true)
        showEaseBar(true)
        resultPanel.reset()
        setResultCollapsed(false, animated: false)
        cardView.conceal()
        controlBar.setTitle("录音", for: .record)
        controlBar.setEnabled(false, for: .playback)
        controlBar.setEnabled(false, for: .score)
        controlBar.setEnabled(false, for: .reference)
        sessionStart = Date()

        do {
            let collection = try AnkiStore.shared.requireCollection()
            guard let next = try collection.nextCard(deckId: deckId) else {
                card = nil
                cardView.reveal()
                setStatus("本牌组今日已完成")
                currentWebNavigation = webView.loadHTMLString(doneHTML(), baseURL: nil)
                return
            }
            card = next
            mode = ModeRouter.mode(for: next, deckHint: deckName)
            easeBar.setIntervals(next.nextIntervals)
            setStatus("\(modeTitle(mode))  ·  \(next.modelName)")
            loadCardSide(reviewHTML(for: next), card: next)
            // Supported modes keep Score tappable so a missing recording produces
            // an explicit prompt instead of looking like a broken control.
            controlBar.setEnabled(mode != .unsupported, for: .score)
            if mode == .pronounce {
                pronounceSession.configure(card: next, deckHint: deckName)
                controlBar.setEnabled(pronounceSession.target != nil, for: .reference)
                controlBar.setEnabled(!playbackMediaQueue.isEmpty, for: .playback)
                pronounceSession.loadReferenceAudio()
            } else {
                pronounceSession.configureRecording(card: next)
                controlBar.setEnabled(referenceAvailable, for: .reference)
                controlBar.setEnabled(!playbackMediaQueue.isEmpty, for: .playback)
            }
        } catch {
            card = nil
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func modeTitle(_ value: PracticeMode) -> String {
        switch value {
        case .pronounce: return "Pronounce"
        case .ielts:
            if let card = card, let part = IELTSSpeakingMode.part(for: card) {
                return "IELTS \(part.displayName)"
            }
            return "IELTS"
        case .compose: return "Compose"
        case .unsupported: return "Anki Review"
        }
    }

    private func loadCardSide(_ html: String, card: AnkiCardSnapshot) {
        stopCardAudio()
        let prepared = prepareCardHTML(html)
        let routes = ModeRouter.audioRoutes(for: card, mode: mode)
        referenceMediaQueue = routes.reference
        playbackMediaQueue = routes.playback
        switch mode {
        case .ielts:
            cardSpeechText = IELTSSpeakingMode.question(for: card)
        case .compose:
            cardSpeechText = ComposeMode.parseKeywords(card: card).joined(separator: " ")
        default:
            cardSpeechText = ""
        }
        currentWebNavigation = webView.loadHTMLString(prepared.html, baseURL: card.mediaDir)
        if mode != .pronounce {
            controlBar.setEnabled(referenceAvailable, for: .reference)
            controlBar.setEnabled(
                pronounceSession.recordingAttachment != nil || !playbackMediaQueue.isEmpty,
                for: .playback
            )
        }
    }

    private func reviewHTML(for card: AnkiCardSnapshot) -> String {
        guard mode == .ielts else { return card.frontHTML }
        let question = IELTSSpeakingMode.question(for: card)
        guard !question.isEmpty else { return card.frontHTML }
        // Do not reveal the original front template: it also contains topic,
        // level and usage instructions. The Question field is the source of truth.
        return """
        <html><body>
        <div class="said-original-label">ORIGINAL QUESTION</div>
        <div class="said-original-question">\(escapeHTML(question))</div>
        </body></html>
        """
    }

    private func toggleRecording() {
        if pronounceSession.isRecording {
            pronounceSession.stopRecording()
            return
        }
        activeIELTSTask?.cancel()
        activeIELTSTask = nil
        player.stop()
        stopCardAudio()
        didAttachCurrentRecording = false
        pronounceSession.startRecording()
    }

    private func playRecording() {
        player.stop()
        stopCardAudio()
        if let url = pronounceSession.recordingAttachment?.fileURL {
            do {
                try player.play(url: url)
                setStatus("正在回放本次录音")
            } catch {
                setStatus("无法回放录音：\(error.localizedDescription)", error: true)
            }
        } else if !playbackMediaQueue.isEmpty {
            playCardMedia(queue: playbackMediaQueue, startingAt: 0, continueQueue: true)
        }
    }

    private func playReference() {
        guard !isRecording else { return }
        player.stop()
        if mode == .pronounce {
            guard let attachment = pronounceSession.referenceAttachment else {
                pronounceSession.loadReferenceAudio()
                return
            }
            playReferenceAttachment(attachment)
        } else if mode == .ielts {
            // QuestionAudio in English_Speaking.apkg is already Edge TTS for the
            // exact Question field. Prefer it and only synthesize when missing.
            if let first = referenceMediaQueue.first {
                playCardMedia(queue: [first], startingAt: 0, continueQueue: false)
            } else {
                speakCardFallback()
            }
        } else if !referenceMediaQueue.isEmpty {
            playCardMedia(queue: referenceMediaQueue, startingAt: 0, continueQueue: true)
        } else if mode == .compose {
            speakCardFallback()
        }
    }

    private func playReferenceAttachment(_ attachment: PronounceAudioAttachment) {
        do {
            try player.play(url: attachment.fileURL)
            setStatus("正在播放已固化的 Edge TTS 参考音")
        } catch {
            setStatus("无法播放参考音：\(error.localizedDescription)", error: true)
        }
    }

    private func renderPronounceSession(_ state: PronounceSessionState) {
        switch state {
        case .idle:
            isRecording = false
            if mode == .pronounce {
                controlBar.setEnabled(pronounceSession.target != nil, for: .reference)
                controlBar.setEnabled(true, for: .score)
            }
        case .loadingReference:
            setStatus("正在读取或生成 Edge TTS 参考音…")
            controlBar.setEnabled(true, for: .reference)
            controlBar.setEnabled(true, for: .score)
        case .ready(let reference):
            // Keep Reference tappable even when generation failed, allowing retry.
            controlBar.setEnabled(pronounceSession.target != nil, for: .reference)
            controlBar.setEnabled(true, for: .score)
            setStatus(reference == nil ? "参考音不可用，可直接录音" : "参考音已就绪")
        case .recording:
            isRecording = true
            controlBar.setTitle("停止", for: .record)
            controlBar.setEnabled(false, for: .reference)
            controlBar.setEnabled(false, for: .playback)
            controlBar.setEnabled(false, for: .score)
            setStatus("录音中…")
            resultPanel.showStatus("正在录音…")
        case .recorded:
            isRecording = false
            controlBar.setTitle("重录", for: .record)
            controlBar.setEnabled(true, for: .playback)
            controlBar.setEnabled(mode != .unsupported, for: .score)
            controlBar.setEnabled(referenceAvailable, for: .reference)
            setStatus("录音完成，可回放或评分")
            resultPanel.showStatus("录音已就绪，评分后显示详细结果")
        case .scoring:
            isRecording = false
            setScoringUI(message: "Azure 发音评分中…")
        case .completed(let entry):
            isRecording = false
            restoreAfterScoring()
            attachCurrentRecordingIfNeeded()
            resultPanel.render(pronounceContent(entry))
            setStatus("Pronounce 评分完成，可再次录音或选择 Anki 难度")
        case .failed(let message, _):
            isRecording = false
            restoreAfterScoring()
            setStatus(message, error: true)
            resultPanel.showStatus(message, isError: true, expand: true)
        case .cancelled:
            isRecording = false
        }
    }

    private var referenceAvailable: Bool {
        if mode == .pronounce { return pronounceSession.target != nil }
        if mode == .ielts { return !cardSpeechText.isEmpty }
        if mode == .compose { return !referenceMediaQueue.isEmpty || !cardSpeechText.isEmpty }
        return !referenceMediaQueue.isEmpty
    }

    private func runScore() {
        guard let card = card,
              let attachment = pronounceSession.recordingAttachment else {
            setStatus("请先录音", error: true)
            return
        }
        switch mode {
        case .pronounce:
            pronounceSession.score()
        case .ielts:
            runIELTS(card: card, recordingURL: attachment.fileURL)
        case .compose:
            runCompose(card: card, recordingURL: attachment.fileURL)
        case .unsupported:
            setStatus("此笔记类型仅提供 Anki 复习，未配置口语评分", error: true)
        }
    }

    private func runIELTS(card: AnkiCardSnapshot, recordingURL: URL) {
        guard let part = IELTSSpeakingMode.part(for: card) else {
            setStatus("IELTS Part 字段必须是 1、2 或 3", error: true)
            return
        }
        let question = IELTSSpeakingMode.question(for: card)
        guard !question.isEmpty else {
            setStatus("IELTS Question 字段为空", error: true)
            return
        }
        let generation = operationGeneration
        setScoringUI(message: "IELTS \(part.displayName) · Azure 转写中…")
        let request = IELTSServiceRequest(
            audioURL: recordingURL,
            question: question,
            part: part,
            duration: pronounceSession.recordingDuration
        )
        activeIELTSTask = ieltsService.score(request, progress: { [weak self] report in
            guard let self = self, self.operationGeneration == generation, report.state == .running else { return }
            self.setStatus("IELTS \(part.displayName) · \(self.stageTitle(report.stage))…")
        }, completion: { [weak self] result in
            guard let self = self, self.operationGeneration == generation else { return }
            self.activeIELTSTask = nil
            self.restoreAfterScoring()
            self.attachCurrentRecordingIfNeeded()
            self.resultPanel.render(self.ieltsContent(result))
            let suffix = result.failedStages.isEmpty ? "" : "（部分服务失败）"
            self.setStatus("IELTS \(part.displayName) 完成\(suffix)，可再次录音或选择 Anki 难度")
        })
    }

    private func stageTitle(_ stage: IELTSStage) -> String {
        switch stage {
        case .transcription: return "Azure 转写"
        case .transcriptRepair: return "Qwen 转写校正"
        case .pronunciation: return "Azure 发音评分"
        case .feedback: return "Qwen 点评"
        }
    }

    private func runCompose(card: AnkiCardSnapshot, recordingURL: URL) {
        let generation = operationGeneration
        setScoringUI(message: "Compose · Azure 转写中…")
        AzureSpeechService.transcribe(wavURL: recordingURL) { [weak self] transcription in
            guard let self = self, self.operationGeneration == generation else { return }
            switch transcription {
            case .failure(let error):
                self.restoreAfterScoring()
                self.setStatus(error.localizedDescription, error: true)
                self.resultPanel.showStatus(error.localizedDescription, isError: true, expand: true)
            case .success(let transcript):
                self.finishCompose(
                    card: card,
                    recordingURL: recordingURL,
                    transcript: transcript,
                    generation: generation
                )
            }
        }
    }

    private func finishCompose(
        card: AnkiCardSnapshot,
        recordingURL: URL,
        transcript: String,
        generation: Int
    ) {
        let keywords = ComposeMode.parseKeywords(card: card)
        let language = ComposeMode.lang(card: card)
        let reference = transcript.isEmpty ? keywords.joined(separator: " ") : transcript
        let group = DispatchGroup()
        var score = ScoreResult(transcript: transcript)
        var qwenError: String?

        group.enter()
        AzureSpeechService.scorePronunciation(wavURL: recordingURL, referenceText: reference) { value in
            score.accuracy = value.accuracy
            score.fluency = value.fluency
            score.completeness = value.completeness
            score.words = value.words
            score.error = value.error
            if score.transcript.isEmpty { score.transcript = value.transcript }
            group.leave()
        }
        group.enter()
        QwenService.fixBetter(
            audioURL: recordingURL,
            prompt: ComposeMode.qwenPrompt(keywords: keywords, lang: language, transcript: transcript),
            transcript: transcript
        ) { result in
            switch result {
            case .success(let value):
                score.llmFix = value.fix
                score.llmBetter = value.better
            case .failure(let error):
                qwenError = error.localizedDescription
            }
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.operationGeneration == generation else { return }
            if let error = qwenError, score.llmFix.isEmpty {
                score.error = [score.error, error].compactMap { $0 }.joined(separator: " | ")
            }
            self.restoreAfterScoring()
            self.attachCurrentRecordingIfNeeded()
            self.resultPanel.render(self.composeContent(score))
            self.setStatus("Compose 完成，可再次录音或选择 Anki 难度")
        }
    }

    private func setScoringUI(message: String) {
        controlBar.setEnabled(false, for: .score)
        controlBar.setEnabled(false, for: .record)
        controlBar.setEnabled(false, for: .playback)
        setStatus(message)
        resultPanel.showStatus(message, expand: true)
    }

    private func restoreAfterScoring() {
        controlBar.setTitle("再次录音", for: .record)
        controlBar.setEnabled(true, for: .record)
        controlBar.setEnabled(
            pronounceSession.recordingAttachment != nil || !playbackMediaQueue.isEmpty,
            for: .playback
        )
        controlBar.setEnabled(mode != .unsupported, for: .score)
        controlBar.setEnabled(referenceAvailable, for: .reference)
    }

    private func attachCurrentRecordingIfNeeded() {
        guard !didAttachCurrentRecording,
              let card = card,
              let url = pronounceSession.recordingAttachment?.fileURL else { return }
        do {
            try AnkiStore.shared.requireCollection().attachRecording(url, to: card)
            didAttachCurrentRecording = true
        } catch {
            setStatus("评分完成，但录音写回失败：\(error.localizedDescription)", error: true)
        }
    }

    private func pronounceContent(_ entry: PronounceHistoryEntry) -> SpeakingResultContent {
        let score = entry.score
        let weak = score.weakestWords.prefix(12).map { word in
            let phonemes = word.phonemes
                .filter { $0.accuracy < 80 }
                .map { "\($0.stressMark)\(PronouncePhonemeNotation.ipa(for: $0.symbol)) \(Int($0.accuracy))" }
                .joined(separator: " · ")
            return SpeakingWeakItem(
                word: word.word,
                score: word.accuracy,
                detail: [word.error, phonemes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }
        var metrics = [
            SpeakingMetric(title: "准确", value: score.accuracy),
            SpeakingMetric(title: "流利", value: score.fluency),
            SpeakingMetric(title: "完整", value: score.completeness)
        ]
        if let prosody = score.prosody { metrics.append(SpeakingMetric(title: "韵律", value: prosody)) }
        return SpeakingResultContent(
            title: "Pronounce · \(entry.target.referenceText)",
            transcript: score.transcript,
            metrics: metrics,
            sections: [],
            weakItems: weak
        )
    }

    private func ieltsContent(_ result: IELTSServiceResult) -> SpeakingResultContent {
        let pronunciation = result.pronunciation
        let metrics = pronunciation.map {
            [
                SpeakingMetric(title: "准确", value: $0.accuracy),
                SpeakingMetric(title: "流利", value: $0.fluency),
                SpeakingMetric(title: "完整", value: $0.completeness)
            ]
        } ?? []
        let weak: [SpeakingWeakItem]
        if let words = pronunciation?.words {
            weak = words.filter {
                $0.accuracy < 80 || !$0.error.isEmpty
            }.prefix(12).map { word in
                let phonemes = word.phonemes.filter { $0.accuracy < 80 }
                    .map { "\(PronouncePhonemeNotation.ipa(for: $0.phoneme)) \(Int($0.accuracy))" }
                    .joined(separator: " · ")
                return SpeakingWeakItem(
                    word: word.word,
                    score: word.accuracy,
                    detail: [word.error, phonemes].filter { !$0.isEmpty }.joined(separator: " · ")
                )
            }
        } else {
            weak = []
        }
        let failures = result.failedStages.compactMap { stage -> String? in
            guard let error = result.stages[stage]?.error else { return nil }
            return "\(stageTitle(stage)): \(error)"
        }.joined(separator: "\n")
        return SpeakingResultContent(
            title: "IELTS \(result.request.part.displayName)",
            transcript: result.displayTranscript,
            metrics: metrics,
            sections: [
                SpeakingResultSection(title: "示范回答", body: result.feedback.modelAnswer),
                SpeakingResultSection(title: "教练点评", body: result.feedback.critique),
                SpeakingResultSection(title: "最小矫正", body: result.feedback.minimalCorrection),
                SpeakingResultSection(title: "部分失败", body: failures)
            ],
            weakItems: weak
        )
    }

    private func composeContent(_ result: ScoreResult) -> SpeakingResultContent {
        SpeakingResultContent(
            title: "Compose",
            transcript: result.transcript,
            metrics: [
                SpeakingMetric(title: "准确", value: result.accuracy),
                SpeakingMetric(title: "流利", value: result.fluency),
                SpeakingMetric(title: "完整", value: result.completeness)
            ],
            sections: [
                SpeakingResultSection(title: "矫正", body: result.llmFix),
                SpeakingResultSection(title: "更自然表达", body: result.llmBetter),
                SpeakingResultSection(title: "提示", body: result.error ?? "")
            ],
            weakItems: weakItems(from: result.words)
        )
    }

    private func weakItems(from words: [[String: Any]]) -> [SpeakingWeakItem] {
        words.compactMap { value in
            let accuracy = number(value["accuracy"])
            guard accuracy < 80 else { return nil }
            let word = value["word"] as? String ?? ""
            let error = value["error"] as? String ?? ""
            let phonemes = (value["phonemes"] as? [[String: Any]] ?? []).compactMap { phoneme -> String? in
                let score = number(phoneme["accuracy"])
                guard score < 80 else { return nil }
                let symbol = phoneme["phoneme"] as? String ?? ""
                return "\(PronouncePhonemeNotation.ipa(for: symbol)) \(Int(score))"
            }.joined(separator: " · ")
            return SpeakingWeakItem(
                word: word,
                score: accuracy,
                detail: [error, phonemes].filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }
    }

    private func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return 0
    }

    private func answer(_ ease: AnkiEase) {
        guard let card = card, !isAnswering else { return }
        isAnswering = true
        setAnswerControlsEnabled(false)
        let elapsed = Int(Date().timeIntervalSince(sessionStart) * 1000)
        do {
            try AnkiStore.shared.requireCollection().answer(
                cardId: card.cardId,
                ease: ease,
                timeMs: max(elapsed, 1000)
            )
            undoControl.isEnabled = true
            loadNext()
        } catch {
            isAnswering = false
            setAnswerControlsEnabled(true)
            setStatus(error.localizedDescription, error: true)
        }
    }

    @objc private func undoLastAnswer() {
        guard undoControl.isEnabled, !isAnswering else { return }
        isAnswering = true
        undoControl.isEnabled = false
        setAnswerControlsEnabled(false)
        do {
            cleanupReviewSession(stopWebView: false)
            try AnkiStore.shared.requireCollection().undo()
            loadNext()
            setStatus("已撤销上一评分")
        } catch {
            isAnswering = false
            undoControl.isEnabled = true
            setAnswerControlsEnabled(true)
            setStatus("无法撤销：\(error.localizedDescription)", error: true)
        }
    }

    private func setAnswerControlsEnabled(_ enabled: Bool) {
        controlBar.setAllEnabled(enabled)
        easeBar.setEnabled(enabled)
        if enabled {
            controlBar.setEnabled(referenceAvailable, for: .reference)
            controlBar.setEnabled(
                pronounceSession.recordingAttachment != nil || !playbackMediaQueue.isEmpty,
                for: .playback
            )
            controlBar.setEnabled(mode != .unsupported, for: .score)
        }
    }

    private func showEaseBar(_ visible: Bool) {
        easeBar.isHidden = !visible
        easeHeight.constant = visible ? 60 : 0
        view.layoutIfNeeded()
    }

    private func setResultCollapsed(_ collapsed: Bool, animated: Bool = true) {
        resultHeight.isActive = collapsed
        webPreferredHeight.isActive = !collapsed
        let changes = { self.view.layoutIfNeeded() }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    private func setStatus(_ text: String, error: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = error ? DSTheme.c.destructive : DSTheme.c.textSecondary
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    @objc private func applicationDidEnterBackground() {
        cleanupReviewSession(stopWebView: false)
        controlBar.setTitle("录音", for: .record)
        controlBar.setEnabled(!playbackMediaQueue.isEmpty, for: .playback)
        controlBar.setEnabled(false, for: .score)
        setStatus("已暂停录音、播放与评分任务")
    }

    private func cleanupReviewSession(stopWebView: Bool) {
        operationGeneration += 1
        activeIELTSTask?.cancel()
        activeIELTSTask = nil
        activeEdgeTTSTask?.cancel()
        activeEdgeTTSTask = nil
        pronounceSession.reset()
        isRecording = false
        player.stop()
        stopCardAudio()
        if stopWebView {
            currentWebNavigation = nil
            webView.stopLoading()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func releaseTransientResources() {
        cleanupReviewSession(stopWebView: true)
        referenceMediaQueue.removeAll()
        playbackMediaQueue.removeAll()
        activeMediaQueue.removeAll()
        cardSpeechText = ""
    }

    private func prepareCardHTML(_ html: String) -> (html: String, speechText: String) {
        var rendered = html
        if let regex = try? NSRegularExpression(pattern: "(?i)\\[sound:([^\\]]+)\\]") {
            rendered = regex.stringByReplacingMatches(
                in: rendered,
                range: NSRange(rendered.startIndex..., in: rendered),
                withTemplate: ""
            )
        }
        let style = cardThemeStyle()
        if let headEnd = rendered.range(of: "</head>", options: .caseInsensitive) {
            rendered.insert(contentsOf: style, at: headEnd.lowerBound)
        } else {
            rendered = style + rendered
        }
        return (rendered, speechText(from: html))
    }

    private func cardThemeStyle() -> String {
        let colors = DSTheme.c
        return """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: \(ThemeManager.shared.mode == .dark ? "dark" : "light"); }
        html, body { background: \(hex(colors.surface)) !important; color: \(hex(colors.textPrimary)) !important;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
        body { margin: 0; padding: 12px 16px; box-sizing: border-box; min-height: 100%; }
        a { color: \(hex(colors.accent)); }
        .said-replay { display:inline-block; padding:7px 11px; margin:4px; border-radius:8px;
          background:\(hex(colors.surfaceHover)); color:\(hex(colors.accent)); text-decoration:none; }
        .said-missing-audio { color:\(hex(colors.textTertiary)); font-size:13px; }
        .said-original-label { margin-top:16px; color:\(hex(colors.textTertiary)); font-size:11px;
          font-weight:600; letter-spacing:.5px; text-align:center; }
        .said-original-question { margin:7px auto 4px; max-width:720px; font-size:21px;
          line-height:1.45; font-weight:600; text-align:center; }
        </style>
        """
    }

    private func doneHTML() -> String {
        cardThemeStyle() + "<html><body><h2>Done</h2><p>本牌组今日已完成。</p></body></html>"
    }

    private func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private func speechText(from html: String) -> String {
        var text = html
        for pattern in [
            "(?is)<(style|script)\\b[^>]*>.*?</\\1>",
            "(?i)\\[sound:[^\\]]+\\]",
            "<[^>]+>"
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }
        text = decodeHTMLEntities(text)
        return String(
            text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .prefix(800)
        )
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func playCardMedia(queue: [URL], startingAt index: Int, continueQueue: Bool) {
        guard queue.indices.contains(index), !isRecording else { return }
        stopCardAudio()
        activeMediaQueue = queue
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let mediaPlayer = try AVAudioPlayer(contentsOf: queue[index])
            cardMediaIndex = index
            cardMediaShouldContinue = continueQueue
            cardMediaPlayer = mediaPlayer
            mediaPlayer.delegate = self
            mediaPlayer.prepareToPlay()
            guard mediaPlayer.play() else { throw EdgeTTSError.noAudio }
        } catch {
            cardMediaPlayer = nil
            setStatus("无法播放卡面录音：\(error.localizedDescription)", error: true)
        }
    }

    private func speakCardFallback() {
        guard !cardSpeechText.isEmpty, !isRecording else { return }
        stopCardAudio()
        setStatus("正在读取或生成 Edge TTS 音频…")
        activeEdgeTTSTask = edgeTTS.synthesize(
            text: cardSpeechText,
            voice: EdgeTTSService.defaultVoice
        ) { [weak self] result in
            guard let self = self else { return }
            self.activeEdgeTTSTask = nil
            switch result {
            case .success(let url):
                do {
                    try self.player.play(url: url)
                    self.setStatus("正在播放已固化的 Edge TTS 音频")
                } catch {
                    self.setStatus("无法播放 Edge TTS 音频：\(error.localizedDescription)", error: true)
                }
            case .failure(let error):
                self.setStatus("Edge TTS 生成失败：\(error.localizedDescription)", error: true)
            }
        }
    }

    private func stopCardAudio() {
        activeEdgeTTSTask?.cancel()
        activeEdgeTTSTask = nil
        cardMediaPlayer?.stop()
        cardMediaPlayer?.delegate = nil
        cardMediaPlayer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === cardMediaPlayer else { return }
        cardMediaPlayer = nil
        let next = cardMediaIndex + 1
        if cardMediaShouldContinue, activeMediaQueue.indices.contains(next) {
            playCardMedia(queue: activeMediaQueue, startingAt: next, continueQueue: true)
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentWebNavigation else { return }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}
