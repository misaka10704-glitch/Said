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
            curtain.setImage(ActionIconFactory.image(.reveal, pointSize: 22), for: .normal)
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
        layer.cornerRadius = 12
        layer.borderWidth = 1
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for action in Action.allCases {
            let button = UIButton(type: .system)
            button.setTitle(action.title, for: .normal)
            button.setImage(ActionIconFactory.image(iconKind(for: action), pointSize: 17), for: .normal)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
            button.titleLabel?.font = DSTheme.titleFont(size: 13)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.78
            button.layer.cornerRadius = 8
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
            let title: String
            switch ease {
            case .again: title = "Again"
            case .hard: title = "Hard"
            case .good: title = "Good"
            case .easy: title = "Easy"
            }
            if let interval = intervals[ease], !interval.isEmpty {
                button.setTitle("\(title)\n\(interval)", for: .normal)
            } else {
                button.setTitle(title, for: .normal)
            }
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
        layer.cornerRadius = 12
        layer.borderWidth = 1
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let values: [(String, AnkiEase, UIColor)] = [
            ("Again", .again, DSTheme.easeAgain),
            ("Hard", .hard, DSTheme.easeHard),
            ("Good", .good, DSTheme.easeGood),
            ("Easy", .easy, DSTheme.easeEasy)
        ]
        for (index, value) in values.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(value.0, for: .normal)
            button.titleLabel?.font = DSTheme.titleFont(size: 12)
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.layer.cornerRadius = 8
            button.layer.borderWidth = 1
            button.tag = index
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons.append((button, value.1, value.2))
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

struct SpeakingResultSection {
    let title: String
    let body: String
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
}

final class SpeakingResultPanel: UIView, ThemeRefreshable {
    var onCollapseChange: ((Bool) -> Void)?
    private let headerButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var dynamicViews: [UIView] = []
    private var renderedContent: SpeakingResultContent?
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
        addText(result.title, font: DSTheme.titleFont(size: 15), color: DSTheme.c.textPrimary)
        if !result.transcript.isEmpty {
            addSection(title: "TRANSCRIPT", body: result.transcript)
        }
        if !result.metrics.isEmpty {
            let metrics = UIStackView()
            metrics.axis = .horizontal
            metrics.distribution = .fillEqually
            metrics.spacing = 8
            result.metrics.forEach { metrics.addArrangedSubview(metricView($0)) }
            addDynamic(metrics)
        }
        result.sections.filter { !$0.body.isEmpty }.forEach {
            addSection(title: $0.title, body: $0.body)
        }
        if !result.weakItems.isEmpty {
            addText("弱项词与音素", font: DSTheme.titleFont(size: 12), color: DSTheme.c.textTertiary)
            result.weakItems.forEach { addWeakItem($0) }
        }
        setCollapsed(false, notify: true)
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
    }

    private func addDynamic(_ view: UIView) {
        dynamicViews.append(view)
        contentStack.addArrangedSubview(view)
    }

    private func addText(_ text: String, font: UIFont, color: UIColor) {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        addDynamic(label)
    }

    private func addSection(title: String, body: String) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = DSTheme.titleFont(size: 11)
        titleLabel.textColor = DSTheme.c.textTertiary
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = DSTheme.bodyFont(size: 14)
        bodyLabel.textColor = DSTheme.c.textSecondary
        bodyLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 4
        addDynamic(stack)
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
        wrapper.backgroundColor = DSTheme.c.surfaceHover
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

    private func addWeakItem(_ item: SpeakingWeakItem) {
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
        addDynamic(wrapper)
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
