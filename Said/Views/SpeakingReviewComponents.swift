import UIKit
import WebKit

final class CardWebView: WKWebView, ThemeRefreshable {
    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = .all
        }
        super.init(frame: .zero, configuration: configuration)
        translatesAutoresizingMaskIntoConstraints = false
        isOpaque = false
        scrollView.alwaysBounceVertical = true
        layer.cornerRadius = DSTheme.cornerRadius
        layer.borderWidth = 1
        clipsToBounds = true
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.surface
        scrollView.backgroundColor = DSTheme.c.surface
        layer.borderColor = DSTheme.c.border.cgColor
    }
}

final class CardRevealView: UIView, ThemeRefreshable {
    let webView = CardWebView()
    var onReveal: (() -> Void)?
    var onConceal: (() -> Void)?

    private let curtain = UIButton(type: .system)
    private(set) var isRevealed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
        applyTheme()
    }

    func conceal() {
        isRevealed = false
        updateCurtainAppearance()
    }

    func reveal() {
        guard !isRevealed else { return }
        isRevealed = true
        updateCurtainAppearance()
        onReveal?()
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.surface
        webView.applyTheme()
        curtain.tintColor = .white
        curtain.setTitleColor(.white, for: .normal)
        updateCurtainAppearance()
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = DSTheme.cornerRadius
        clipsToBounds = true
        addSubview(webView)

        curtain.translatesAutoresizingMaskIntoConstraints = false
        curtain.setImage(ActionIconFactory.image(.reveal, pointSize: 22), for: .normal)
        curtain.setTitle("  点击显示问题 / 句子", for: .normal)
        curtain.titleLabel?.font = DSTheme.titleFont(size: 15)
        curtain.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        addSubview(curtain)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            curtain.topAnchor.constraint(equalTo: topAnchor),
            curtain.leadingAnchor.constraint(equalTo: leadingAnchor),
            curtain.trailingAnchor.constraint(equalTo: trailingAnchor),
            curtain.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        conceal()
    }

    @objc private func revealTapped() {
        if isRevealed {
            conceal()
            onConceal?()
        } else {
            reveal()
        }
    }

    private func updateCurtainAppearance() {
        curtain.isHidden = false
        if isRevealed {
            curtain.backgroundColor = .clear
            curtain.setImage(nil, for: .normal)
            curtain.setTitle(nil, for: .normal)
            curtain.accessibilityLabel = "重新遮住问题或句子"
        } else {
            curtain.backgroundColor = .black
            curtain.setImage(ActionIconFactory.image(.reveal, pointSize: 20), for: .normal)
            curtain.setTitle("  点击显示问题 / 句子", for: .normal)
            curtain.accessibilityLabel = "显示问题或句子"
        }
    }
}

final class ReviewControlBar: UIView, ThemeRefreshable {
    enum Action: CaseIterable {
        case reference, record, playback, score

        var title: String {
            switch self {
            case .reference: return "参考音"
            case .record: return "录音"
            case .playback: return "回放"
            case .score: return "评分"
            }
        }
    }

    var onAction: ((Action) -> Void)?
    private let stack = UIStackView()
    private var buttons: [Action: UIButton] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
        applyTheme()
    }

    func setEnabled(_ enabled: Bool, for action: Action) {
        buttons[action]?.isEnabled = enabled
    }

    func setTitle(_ title: String, for action: Action) {
        buttons[action]?.setTitle(title, for: .normal)
        buttons[action]?.accessibilityLabel = title
    }

    func setAllEnabled(_ enabled: Bool) {
        buttons.values.forEach { $0.isEnabled = enabled }
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.surface
        layer.borderColor = DSTheme.c.border.cgColor
        for (action, button) in buttons {
            let accent: UIColor
            switch action {
            case .record: accent = DSTheme.pronounceCoral
            case .score: accent = DSTheme.c.accent
            default: accent = DSTheme.c.textPrimary
            }
            button.setTitleColor(accent, for: .normal)
            button.setTitleColor(DSTheme.c.textTertiary, for: .disabled)
            button.backgroundColor = DSTheme.c.surfaceHover
            button.layer.borderColor = DSTheme.c.border.cgColor
        }
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = DSTheme.cornerRadius
        layer.borderWidth = 1
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = DSTheme.Spacing.xxs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for action in Action.allCases {
            let button = UIButton(type: .system)
            button.setTitle(action.title, for: .normal)
            button.setImage(ActionIconFactory.image(iconKind(for: action), pointSize: 16), for: .normal)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
            button.titleLabel?.font = DSTheme.titleFont(size: 13)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.78
            button.layer.cornerRadius = DSTheme.Form.cornerRadius
            button.layer.borderWidth = 1
            button.accessibilityLabel = action.title
            button.tag = Action.allCases.firstIndex(of: action) ?? 0
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons[action] = button
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    private func iconKind(for action: Action) -> ActionIconFactory.Kind {
        switch action {
        case .reference: return .referenceAudio
        case .record: return .record
        case .playback: return .playback
        case .score: return .score
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        let actions = Action.allCases
        guard actions.indices.contains(sender.tag) else { return }
        onAction?(actions[sender.tag])
    }
}

final class AnswerEaseBar: UIView, ThemeRefreshable {
    var onEase: ((AnkiEase) -> Void)?
    private let stack = UIStackView()
    private var buttons: [(UIButton, AnkiEase, UIColor)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
        applyTheme()
    }

    func setEnabled(_ enabled: Bool) {
        buttons.forEach { $0.0.isEnabled = enabled }
    }

    func setIntervals(_ intervals: [AnkiEase: String]) {
        buttons.forEach { button, ease, _ in
            let title = Self.title(for: ease)
            if let interval = intervals[ease], !interval.isEmpty {
                button.setTitle("\(title)\n\(interval)", for: .normal)
                button.accessibilityLabel = "\(title)，下次间隔 \(interval)"
            } else {
                button.setTitle(title, for: .normal)
                button.accessibilityLabel = title
            }
            button.accessibilityHint = "使用此记忆程度回答当前卡片"
        }
    }

    private static func title(for ease: AnkiEase) -> String {
        switch ease {
        case .again: return "重来"
        case .hard: return "困难"
        case .good: return "良好"
        case .easy: return "简单"
        }
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.surface
        layer.borderColor = DSTheme.c.border.cgColor
        buttons.forEach { button, _, color in
            button.setTitleColor(color, for: .normal)
            button.setTitleColor(DSTheme.c.textTertiary, for: .disabled)
            button.backgroundColor = DSTheme.tintedSurface(color, alpha: 0.13)
            button.layer.borderColor = color.withAlphaComponent(0.5).cgColor
        }
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = DSTheme.cornerRadius
        layer.borderWidth = 1
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = DSTheme.Spacing.xxs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let values: [(AnkiEase, UIColor)] = [
            (.again, DSTheme.easeAgain),
            (.hard, DSTheme.easeHard),
            (.good, DSTheme.easeGood),
            (.easy, DSTheme.easeEasy)
        ]
        for (index, value) in values.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(Self.title(for: value.0), for: .normal)
            button.titleLabel?.font = DSTheme.titleFont(size: 12)
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.layer.cornerRadius = DSTheme.Form.cornerRadius
            button.layer.borderWidth = 1
            button.tag = index
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons.append((button, value.0, value.1))
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @objc private func tapped(_ sender: UIButton) {
        guard buttons.indices.contains(sender.tag) else { return }
        onEase?(buttons[sender.tag].1)
    }
}

struct SpeakingMetric {
    let title: String
    let value: Double
}

enum SpeakingResultSectionStyle {
    case neutral
    case azure
    case qwenModel
    case qwenCorrection
    case qwenImprovement
    case qwenCoach
    case error
}

struct SpeakingResultSection {
    let title: String
    let body: String
    let style: SpeakingResultSectionStyle

    init(title: String, body: String, style: SpeakingResultSectionStyle = .neutral) {
        self.title = title
        self.body = body
        self.style = style
    }
}

struct SpeakingWeakItem {
    let word: String
    let score: Double
    let detail: String
}

struct SpeakingResultContent {
    let title: String
    let transcript: String
    let metrics: [SpeakingMetric]
    let sections: [SpeakingResultSection]
    let weakItems: [SpeakingWeakItem]
    let pronunciationWords: [PronunciationWordScore]

    init(
        title: String,
        transcript: String,
        metrics: [SpeakingMetric],
        sections: [SpeakingResultSection],
        weakItems: [SpeakingWeakItem],
        pronunciationWords: [PronunciationWordScore] = []
    ) {
        self.title = title
        self.transcript = transcript
        self.metrics = metrics
        self.sections = sections
        self.weakItems = weakItems
        self.pronunciationWords = pronunciationWords
    }
}

final class SpeakingResultPanel: UIView, ThemeRefreshable {
    var onCollapseChange: ((Bool) -> Void)?
    private let headerButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var dynamicViews: [UIView] = []
    private var renderedContent: SpeakingResultContent?
    private var ieltsColumns: UIStackView?
    private var statusIsError = false
    private(set) var isCollapsed = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
        applyTheme()
    }

    func reset(message: String = "录音后可在这里查看口语结果") {
        renderedContent = nil
        statusIsError = false
        clearDynamicViews()
        statusLabel.text = message
        statusLabel.isHidden = false
        setCollapsed(false, notify: false)
    }

    func showStatus(_ message: String, isError: Bool = false, expand: Bool = false) {
        renderedContent = nil
        statusIsError = isError
        clearDynamicViews()
        statusLabel.text = message
        statusLabel.textColor = isError ? DSTheme.c.destructive : DSTheme.c.textSecondary
        statusLabel.isHidden = false
        if expand { setCollapsed(false, notify: true) }
    }

    func render(_ result: SpeakingResultContent) {
        renderedContent = result
        statusIsError = false
        clearDynamicViews()
        statusLabel.isHidden = true
        if result.title.hasPrefix("IELTS") {
            renderIELTS(result)
            setCollapsed(isCollapsed, notify: true)
            return
        }
        addText(result.title, font: DSTheme.titleFont(size: 15), color: DSTheme.c.textPrimary)
        if !result.transcript.isEmpty {
            addSection(title: "AZURE TRANSCRIPT", body: result.transcript, style: .azure)
        }
        if !result.metrics.isEmpty {
            let metrics = UIStackView()
            metrics.axis = .horizontal
            metrics.distribution = .fillEqually
            metrics.alignment = .fill
            metrics.spacing = 6
            result.metrics.forEach { metrics.addArrangedSubview(metricView($0)) }
            addDynamic(metrics)
        }
        result.sections.filter { !$0.body.isEmpty }.forEach {
            addSection(title: $0.title, body: $0.body, style: $0.style)
        }
        if !result.pronunciationWords.isEmpty {
            addText(
                "AZURE 发音明细",
                font: DSTheme.titleFont(size: 12),
                color: DSTheme.voiceBlue
            )
            addText(
                "绿≥80 黄60–79 红<60 · '主重音 ,次重音 · ⏸异常停顿 ⇥缺停顿 →单调",
                font: DSTheme.bodyFont(size: 11),
                color: DSTheme.c.textSecondary
            )
            addPronunciationDetails(result.pronunciationWords)
        }
        if result.pronunciationWords.isEmpty, !result.weakItems.isEmpty {
            addText("弱项词与音素", font: DSTheme.titleFont(size: 12), color: DSTheme.c.textTertiary)
            result.weakItems.forEach { addWeakItem($0) }
        }
        setCollapsed(isCollapsed, notify: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateIELTSColumnsLayout()
    }

    private func renderIELTS(_ result: SpeakingResultContent) {
        addText(result.title, font: DSTheme.titleFont(size: 15), color: DSTheme.c.textPrimary)

        let azure = UIStackView()
        azure.axis = .vertical
        azure.spacing = 8
        let qwen = UIStackView()
        qwen.axis = .vertical
        qwen.spacing = 8

        if !result.transcript.isEmpty {
            addSection(title: "AZURE TRANSCRIPT", body: result.transcript, style: .azure, to: azure)
        }
        if !result.metrics.isEmpty {
            let metrics = UIStackView()
            metrics.axis = .horizontal
            metrics.distribution = .fillEqually
            metrics.alignment = .fill
            metrics.spacing = 6
            result.metrics.forEach { metrics.addArrangedSubview(metricView($0)) }
            add(metrics, to: azure)
        }
        if !result.pronunciationWords.isEmpty {
            addText(
                "AZURE 发音明细",
                font: DSTheme.titleFont(size: 12),
                color: DSTheme.voiceBlue,
                to: azure
            )
            addPronunciationDetails(result.pronunciationWords, to: azure)
        } else if !result.weakItems.isEmpty {
            addText("弱项词与音素", font: DSTheme.titleFont(size: 12), color: DSTheme.c.textTertiary, to: azure)
            result.weakItems.forEach { addWeakItem($0, to: azure) }
        }

        result.sections.filter { !$0.body.isEmpty }.forEach {
            addSection(title: $0.title, body: $0.body, style: $0.style, to: qwen)
        }

        let columns = UIStackView(arrangedSubviews: [azure, qwen])
        columns.spacing = 12
        ieltsColumns = columns
        updateIELTSColumnsLayout()
        addDynamic(columns)
    }

    private func updateIELTSColumnsLayout() {
        guard let columns = ieltsColumns else { return }
        let windowBounds = window?.bounds ?? bounds
        let landscape = windowBounds.width > windowBounds.height
        columns.axis = landscape ? .horizontal : .vertical
        columns.distribution = landscape ? .fillEqually : .fill
        // In landscape, filling the cross-axis stretches the shorter Qwen
        // column to Azure's height and can expand its first answer card.
        columns.alignment = landscape ? .top : .fill
    }

    func setCollapsed(_ collapsed: Bool, notify: Bool) {
        isCollapsed = collapsed
        scrollView.isHidden = collapsed
        headerButton.setTitle("  口语结果", for: .normal)
        headerButton.setImage(
            ActionIconFactory.image(collapsed ? .expand : .collapse, pointSize: 15),
            for: .normal
        )
        headerButton.accessibilityLabel = collapsed ? "展开口语结果" : "折叠口语结果"
        if notify { onCollapseChange?(collapsed) }
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.surface
        layer.borderColor = DSTheme.c.border.cgColor
        headerButton.setTitleColor(DSTheme.c.textPrimary, for: .normal)
        statusLabel.textColor = statusIsError ? DSTheme.c.destructive : DSTheme.c.textSecondary
        scrollView.backgroundColor = DSTheme.c.surface
        if let content = renderedContent {
            let collapsed = isCollapsed
            render(content)
            setCollapsed(collapsed, notify: true)
        }
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.borderWidth = 1
        clipsToBounds = true
        headerButton.contentHorizontalAlignment = .left
        headerButton.titleLabel?.font = DSTheme.titleFont(size: 13)
        headerButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)
        addSubview(headerButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        statusLabel.font = DSTheme.bodyFont(size: 13)
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)
        NSLayoutConstraint.activate([
            headerButton.topAnchor.constraint(equalTo: topAnchor),
            headerButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerButton.heightAnchor.constraint(equalToConstant: 42),
            scrollView.topAnchor.constraint(equalTo: headerButton.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 2),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -12),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -24)
        ])
        reset()
    }

    private func clearDynamicViews() {
        dynamicViews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        dynamicViews.removeAll()
        ieltsColumns = nil
    }

    private func addDynamic(_ view: UIView) {
        dynamicViews.append(view)
        contentStack.addArrangedSubview(view)
    }

    private func addText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        to target: UIStackView? = nil
    ) {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        add(label, to: target)
    }

    private func add(_ view: UIView, to target: UIStackView?) {
        if let target = target {
            target.addArrangedSubview(view)
        } else {
            addDynamic(view)
        }
    }

    private func addSection(
        title: String,
        body: String,
        style: SpeakingResultSectionStyle = .neutral,
        to target: UIStackView? = nil
    ) {
        let color = sectionColor(style)
        let isCompactQwen: Bool
        switch style {
        case .qwenModel, .qwenCoach, .qwenCorrection, .qwenImprovement:
            isCompactQwen = true
        default:
            isCompactQwen = false
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = DSTheme.titleFont(size: 11)
        titleLabel.textColor = color
        let bodyLabel = UILabel()
        // AI responses can include a leading newline.  It becomes particularly
        // conspicuous in the two-column IELTS layout, so remove only outer
        // whitespace while keeping paragraph breaks inside the answer.
        bodyLabel.text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        bodyLabel.font = DSTheme.bodyFont(size: 14)
        bodyLabel.textColor = style == .neutral ? DSTheme.c.textSecondary : color
        bodyLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = isCompactQwen ? 2 : 4
        if style == .neutral {
            add(stack, to: target)
            return
        }
        let wrapper = UIView()
        wrapper.backgroundColor = color.withAlphaComponent(
            ThemeManager.shared.mode == .dark
                ? (isCompactQwen ? 0.08 : 0.12)
                : (isCompactQwen ? 0.05 : 0.08)
        )
        wrapper.layer.cornerRadius = isCompactQwen ? 6 : 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)
        let verticalInset: CGFloat = isCompactQwen ? 5 : 8
        let horizontalInset: CGFloat = isCompactQwen ? 7 : 9
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: verticalInset),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -horizontalInset),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -verticalInset)
        ])
        add(wrapper, to: target)
    }

    private func addPronunciationDetails(
        _ words: [PronunciationWordScore],
        to target: UIStackView? = nil
    ) {
        let horizontalScroll = UIScrollView()
        horizontalScroll.alwaysBounceHorizontal = true
        horizontalScroll.showsHorizontalScrollIndicator = true
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        horizontalScroll.addSubview(container)
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        words.forEach { row.addArrangedSubview(pronunciationWordView($0)) }
        let hasProsodyFeedback = words.contains { !realProsodyErrors($0).isEmpty }
        horizontalScroll.heightAnchor.constraint(
            equalToConstant: hasProsodyFeedback ? 82 : 64
        ).isActive = true
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.bottomAnchor),
            container.heightAnchor.constraint(equalTo: horizontalScroll.frameLayoutGuide.heightAnchor),
            container.widthAnchor.constraint(
                greaterThanOrEqualTo: horizontalScroll.frameLayoutGuide.widthAnchor
            ),
            container.widthAnchor.constraint(greaterThanOrEqualTo: row.widthAnchor, constant: 16),
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])
        add(horizontalScroll, to: target)
    }

    private func pronunciationWordView(_ word: PronunciationWordScore) -> UIView {
        let presentation = wordErrorPresentation(word.error, score: word.accuracy)
        let wordLabel = UILabel()
        let message = presentation.message.isEmpty ? "" : " · \(presentation.message)"
        wordLabel.text = "\(presentation.mark) \(word.word) \(Int(word.accuracy))\(message)"
        wordLabel.font = DSTheme.titleFont(size: 13)
        wordLabel.textColor = presentation.color
        wordLabel.textAlignment = .center
        wordLabel.numberOfLines = 1

        let phonemeStack = UIStackView()
        phonemeStack.axis = .horizontal
        phonemeStack.alignment = .center
        phonemeStack.spacing = 7
        word.phonemes.forEach { phoneme in
            let symbol = UILabel()
            symbol.text = "\(phoneme.stressMark)\(PronouncePhonemeNotation.ipa(for: phoneme.symbol))"
            symbol.font = DSTheme.monoFont(size: 13)
            symbol.textAlignment = .center
            symbol.textColor = scoreColor(phoneme.accuracy)

            let score = UILabel()
            score.text = "\(Int(phoneme.accuracy))"
            score.font = DSTheme.monoFont(size: 10)
            score.textAlignment = .center
            score.textColor = scoreColor(phoneme.accuracy)

            let column = UIStackView(arrangedSubviews: [symbol, score])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 1
            phonemeStack.addArrangedSubview(column)
        }
        if word.phonemes.isEmpty {
            let label = UILabel()
            label.text = word.error == "Omission" ? "无音素返回" : "—"
            label.font = DSTheme.bodyFont(size: 11)
            label.textColor = DSTheme.c.textTertiary
            label.textAlignment = .center
            phonemeStack.addArrangedSubview(label)
        }

        var rows: [UIView] = [wordLabel, phonemeStack]
        if let prosody = prosodyIndicator(for: word) {
            let label = UILabel()
            label.attributedText = prosody
            label.font = DSTheme.bodyFont(size: 10)
            label.textAlignment = .center
            rows.append(label)
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        return stack
    }

    private func prosodyIndicator(for word: PronunciationWordScore) -> NSAttributedString? {
        let errors = realProsodyErrors(word)
        guard !errors.isEmpty else { return nil }
        let output = NSMutableAttributedString()
        for error in errors {
            let text: String
            let color: UIColor
            switch error {
            case "UnexpectedBreak":
                let duration: String
                if let value = word.breakLength, value > 0 {
                    let seconds = value > 10 ? value / 1_000 : value
                    duration = String(format: " %.2fs", seconds)
                } else {
                    duration = ""
                }
                text = "⏸ 异常停顿\(duration)"
                color = DSTheme.c.destructive
            case "MissingBreak":
                text = "⇥ 缺停顿"
                color = DSTheme.c.warning
            case "Monotone":
                text = "→ 单调"
                color = DSTheme.speakingViolet
            default:
                text = "! \(error)"
                color = DSTheme.c.warning
            }
            if output.length > 0 {
                output.append(NSAttributedString(string: "  "))
            }
            output.append(NSAttributedString(
                string: text,
                attributes: [.foregroundColor: color]
            ))
        }
        return output
    }

    private func realProsodyErrors(_ word: PronunciationWordScore) -> [String] {
        (word.prosodyErrors ?? []).filter {
            let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && normalized != "none"
        }
    }

    private func metricView(_ metric: SpeakingMetric) -> UIView {
        let title = UILabel()
        title.text = metric.title
        title.textAlignment = .center
        title.font = DSTheme.bodyFont(size: 11)
        title.textColor = DSTheme.c.textTertiary
        let value = UILabel()
        value.text = String(format: "%.0f", metric.value)
        value.textAlignment = .center
        value.font = DSTheme.titleFont(size: 21)
        value.textColor = scoreColor(metric.value)
        let stack = UIStackView(arrangedSubviews: [title, value])
        stack.axis = .vertical
        stack.spacing = 2
        let wrapper = UIView()
        wrapper.backgroundColor = scoreColor(metric.value).withAlphaComponent(
            ThemeManager.shared.mode == .dark ? 0.22 : 0.12
        )
        wrapper.layer.cornerRadius = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -7)
        ])
        return wrapper
    }

    private func addWeakItem(_ item: SpeakingWeakItem, to target: UIStackView? = nil) {
        let label = UILabel()
        let detail = item.detail.isEmpty ? "" : "\n\(item.detail)"
        label.text = "\(item.word)  \(Int(item.score))\(detail)"
        label.font = DSTheme.bodyFont(size: 13)
        label.textColor = scoreColor(item.score)
        label.numberOfLines = 0
        let wrapper = UIView()
        wrapper.backgroundColor = DSTheme.c.surfaceHover
        wrapper.layer.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 7),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -9),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -7)
        ])
        add(wrapper, to: target)
    }

    private func sectionColor(_ style: SpeakingResultSectionStyle) -> UIColor {
        switch style {
        case .neutral: return DSTheme.c.textTertiary
        case .azure, .qwenModel: return DSTheme.voiceBlue
        case .qwenCorrection: return DSTheme.c.warning
        case .qwenImprovement: return DSTheme.c.success
        case .qwenCoach: return DSTheme.speakingViolet
        case .error: return DSTheme.c.destructive
        }
    }

    private func wordErrorPresentation(
        _ error: String?,
        score: Double
    ) -> (mark: String, message: String, color: UIColor) {
        switch error {
        case "Omission":
            return ("✗", "遗漏", DSTheme.c.destructive)
        case "Insertion":
            return ("~", "多读", DSTheme.learningAmber)
        case "Mispronunciation":
            return ("~", "发音错误", DSTheme.learningAmber)
        case .some(let value) where !value.isEmpty && value != "None":
            return ("~", value, DSTheme.learningAmber)
        default:
            return ("✓", "", scoreColor(score))
        }
    }

    private func scoreColor(_ score: Double) -> UIColor {
        if score >= 80 { return DSTheme.c.success }
        if score >= 60 { return DSTheme.c.warning }
        return DSTheme.c.destructive
    }

    @objc private func toggleCollapsed() {
        setCollapsed(!isCollapsed, notify: true)
    }
}
