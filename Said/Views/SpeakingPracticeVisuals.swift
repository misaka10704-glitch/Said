import UIKit

final class DeckListSummaryHeaderView: UIView {
    private let summaryLabel = UILabel()
    private let newColumn = DeckCountSummaryColumn(prefix: "新", color: DSTheme.voiceBlue)
    private let learningColumn = DeckCountSummaryColumn(prefix: "学", color: DSTheme.learningAmber)
    private let reviewColumn = DeckCountSummaryColumn(prefix: "复", color: DSTheme.brandCyan)
    private let bottomDivider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    func configure(nodes: [DeckManagementNode]) {
        let roots = nodes.count
        let all = flattened(nodes)
        summaryLabel.text = "\(roots) 个顶层牌组 · \(all.count) 个牌组"
        newColumn.value = nodes.reduce(0) { $0 + $1.newCount }
        learningColumn.value = nodes.reduce(0) { $0 + $1.learningCount }
        reviewColumn.value = nodes.reduce(0) { $0 + $1.reviewCount }
        accessibilityLabel = [
            summaryLabel.text,
            "新 \(newColumn.value)",
            "学 \(learningColumn.value)",
            "复 \(reviewColumn.value)"
        ].compactMap { $0 }.joined(separator: "，")
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.background
        summaryLabel.textColor = DSTheme.c.textTertiary
        bottomDivider.backgroundColor = DSTheme.c.divider
        newColumn.applyTheme()
        learningColumn.applyTheme()
        reviewColumn.applyTheme()
    }

    private func build() {
        isAccessibilityElement = true
        summaryLabel.font = DSTheme.bodyFont(size: 12)
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let counts = UIStackView(arrangedSubviews: [newColumn, learningColumn, reviewColumn])
        counts.axis = .horizontal
        counts.spacing = DSTheme.DeckCounts.columnSpacing
        counts.alignment = .center

        // Mirror DeckTreeRowCell's more-button width so count columns share an axis.
        let moreSpacer = UIView()
        moreSpacer.translatesAutoresizingMaskIntoConstraints = false
        moreSpacer.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let trailing = UIStackView(arrangedSubviews: [counts, moreSpacer])
        trailing.axis = .horizontal
        trailing.alignment = .center
        trailing.spacing = 2

        let stack = UIStackView(arrangedSubviews: [summaryLabel, trailing])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DSTheme.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(bottomDivider)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: DSTheme.DeckCounts.leadingInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: DSTheme.DeckCounts.leadingInset),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: DSTheme.List.separatorHeight)
        ])
        applyTheme()
    }

    private func flattened(_ nodes: [DeckManagementNode]) -> [DeckManagementNode] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }
}

private final class DeckCountSummaryColumn: UIView {
    private let prefixLabel = UILabel()
    private let valueLabel = UILabel()
    private let color: UIColor

    var value: Int = 0 {
        didSet {
            valueLabel.text = "\(value)"
            valueLabel.alpha = value == 0 ? 0.38 : 1
        }
    }

    init(prefix: String, color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        prefixLabel.text = prefix
        prefixLabel.font = DSTheme.titleFont(size: 10)
        prefixLabel.textAlignment = .center
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [prefixLabel, valueLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: DSTheme.DeckCounts.columnWidth)
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        prefixLabel.textColor = color.withAlphaComponent(0.72)
        valueLabel.textColor = color
    }
}

final class DeckTreeRowCell: UITableViewCell {
    static let reuseIdentifier = "DeckTreeRowCell"

    private let disclosureButton = UIButton(type: .system)
    private let accentView = UIView()
    private let titleLabel = UILabel()
    private let filteredBadge = UILabel()
    private let newLabel = UILabel()
    private let learningLabel = UILabel()
    private let reviewLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private var leadingConstraint: NSLayoutConstraint!
    private var disclosureAction: (() -> Void)?
    private var moreAction: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        node: DeckManagementNode,
        depth: Int,
        expanded: Bool,
        disclosureAction: @escaping () -> Void,
        moreAction: @escaping () -> Void
    ) {
        self.disclosureAction = disclosureAction
        self.moreAction = moreAction
        let shortName = node.name.components(separatedBy: "::").last ?? node.name
        titleLabel.text = shortName
        filteredBadge.isHidden = !node.filtered
        accentView.backgroundColor = DSTheme.practiceAccent(deckName: node.name)
        leadingConstraint.constant = 8 + CGFloat(min(depth, 8)) * 16
        disclosureButton.isHidden = node.children.isEmpty
        disclosureButton.setTitle(expanded ? "▾" : "▸", for: .normal)
        configureCount(newLabel, value: node.newCount)
        configureCount(learningLabel, value: node.learningCount)
        configureCount(reviewLabel, value: node.reviewCount)
        accessibilityLabel = "\(node.name)，新 \(node.newCount)，学习 \(node.learningCount)，复习 \(node.reviewCount)"
        accessibilityHint = node.children.isEmpty ? "轻点开始学习，长按管理牌组" : "轻点展开或收起，长按管理牌组"
        applyTheme()
    }

    func applyTheme() {
        let colors = DSTheme.c
        backgroundColor = colors.background
        contentView.backgroundColor = colors.background
        titleLabel.textColor = colors.textPrimary
        filteredBadge.textColor = colors.warning
        filteredBadge.backgroundColor = DSTheme.tintedSurface(colors.warning, alpha: 0.16)
        disclosureButton.tintColor = colors.textTertiary
        disclosureButton.setTitleColor(colors.textTertiary, for: .normal)
        moreButton.tintColor = colors.textTertiary
        moreButton.setTitleColor(colors.textTertiary, for: .normal)
        newLabel.textColor = DSTheme.voiceBlue
        learningLabel.textColor = DSTheme.learningAmber
        reviewLabel.textColor = DSTheme.brandCyan
        let selected = UIView()
        selected.backgroundColor = colors.surfaceHover
        selectedBackgroundView = selected
    }

    @objc private func disclose() {
        disclosureAction?()
    }

    @objc private func showMore() {
        moreAction?()
    }

    private func configureCount(_ label: UILabel, value: Int) {
        label.text = "\(value)"
        label.alpha = value == 0 ? 0.38 : 1
    }

    private func build() {
        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        contentView.layoutMargins = .zero
        disclosureButton.setTitle("▸", for: .normal)
        disclosureButton.titleLabel?.font = DSTheme.titleFont(size: 14)
        disclosureButton.addTarget(self, action: #selector(disclose), for: .touchUpInside)
        disclosureButton.accessibilityLabel = "展开或收起"
        accentView.layer.cornerRadius = 2
        titleLabel.font = DSTheme.titleFont(size: 15)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        filteredBadge.text = "筛选"
        filteredBadge.font = DSTheme.titleFont(size: 10)
        filteredBadge.textAlignment = .center
        filteredBadge.layer.cornerRadius = 4
        filteredBadge.clipsToBounds = true
        filteredBadge.setContentHuggingPriority(.required, for: .horizontal)
        [newLabel, learningLabel, reviewLabel].forEach {
            $0.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            $0.textAlignment = .center
            $0.widthAnchor.constraint(equalToConstant: DSTheme.DeckCounts.columnWidth).isActive = true
        }
        moreButton.setTitle("···", for: .normal)
        moreButton.titleLabel?.font = DSTheme.titleFont(size: 18)
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)
        moreButton.accessibilityLabel = "更多操作"

        let badgeWidth = filteredBadge.widthAnchor.constraint(equalToConstant: 34)
        badgeWidth.priority = .defaultHigh
        let badgeHeight = filteredBadge.heightAnchor.constraint(equalToConstant: 18)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, filteredBadge])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 8
        let counts = UIStackView(arrangedSubviews: [newLabel, learningLabel, reviewLabel])
        counts.axis = .horizontal
        counts.spacing = DSTheme.DeckCounts.columnSpacing
        counts.alignment = .center
        [disclosureButton, accentView, titleStack, counts, moreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        leadingConstraint = disclosureButton.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: 8
        )
        NSLayoutConstraint.activate([
            badgeWidth,
            badgeHeight,
            leadingConstraint,
            disclosureButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 24),
            disclosureButton.heightAnchor.constraint(equalToConstant: 36),
            accentView.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 2),
            accentView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accentView.widthAnchor.constraint(equalToConstant: 3),
            accentView.heightAnchor.constraint(equalToConstant: 18),
            titleStack.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 8),
            titleStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            counts.leadingAnchor.constraint(greaterThanOrEqualTo: titleStack.trailingAnchor, constant: 8),
            counts.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.leadingAnchor.constraint(equalTo: counts.trailingAnchor, constant: 2),
            moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 36),
            moreButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        applyTheme()
    }
}
