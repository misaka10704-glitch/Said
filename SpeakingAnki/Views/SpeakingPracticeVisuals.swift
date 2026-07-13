import UIKit

final class DeckListSummaryHeaderView: UIView {
    private let summaryLabel = UILabel()
    private let newLabel = UILabel()
    private let learningLabel = UILabel()
    private let reviewLabel = UILabel()

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
        newLabel.text = "新 \(nodes.reduce(0) { $0 + $1.newCount })"
        learningLabel.text = "学 \(nodes.reduce(0) { $0 + $1.learningCount })"
        reviewLabel.text = "复 \(nodes.reduce(0) { $0 + $1.reviewCount })"
        accessibilityLabel = [
            summaryLabel.text,
            newLabel.text,
            learningLabel.text,
            reviewLabel.text
        ].compactMap { $0 }.joined(separator: "，")
    }

    func applyTheme() {
        backgroundColor = DSTheme.c.background
        summaryLabel.textColor = DSTheme.c.textSecondary
        newLabel.textColor = DSTheme.voiceBlue
        learningLabel.textColor = DSTheme.learningAmber
        reviewLabel.textColor = DSTheme.brandCyan
    }

    private func build() {
        isAccessibilityElement = true
        summaryLabel.font = DSTheme.bodyFont(size: 13)
        [newLabel, learningLabel, reviewLabel].forEach {
            $0.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        }
        let counts = UIStackView(arrangedSubviews: [newLabel, learningLabel, reviewLabel])
        counts.axis = .horizontal
        counts.spacing = 15
        let stack = UIStackView(arrangedSubviews: [summaryLabel, counts])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyTheme()
    }

    private func flattened(_ nodes: [DeckManagementNode]) -> [DeckManagementNode] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }
}

final class DeckTreeRowCell: UITableViewCell {
    static let reuseIdentifier = "DeckTreeRowCell"

    private let disclosureButton = UIButton(type: .system)
    private let accentView = UIView()
    private let titleLabel = UILabel()
    private let filteredLabel = UILabel()
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
        filteredLabel.isHidden = !node.filtered
        accentView.backgroundColor = DSTheme.practiceAccent(deckName: node.name)
        leadingConstraint.constant = 10 + CGFloat(min(depth, 8)) * 18
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
        backgroundColor = DSTheme.c.background
        contentView.backgroundColor = DSTheme.c.background
        titleLabel.textColor = DSTheme.c.textPrimary
        filteredLabel.textColor = DSTheme.c.warning
        disclosureButton.tintColor = DSTheme.c.textSecondary
        moreButton.tintColor = DSTheme.c.textSecondary
        newLabel.textColor = DSTheme.voiceBlue
        learningLabel.textColor = DSTheme.learningAmber
        reviewLabel.textColor = DSTheme.brandCyan
        let selected = UIView()
        selected.backgroundColor = DSTheme.c.surfaceHover
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
        label.alpha = value == 0 ? 0.42 : 1
    }

    private func build() {
        disclosureButton.setTitle("▸", for: .normal)
        disclosureButton.titleLabel?.font = DSTheme.titleFont(size: 15)
        disclosureButton.addTarget(self, action: #selector(disclose), for: .touchUpInside)
        disclosureButton.accessibilityLabel = "展开或收起"
        accentView.layer.cornerRadius = 2
        titleLabel.font = DSTheme.bodyFont(size: 15)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        filteredLabel.text = "筛选"
        filteredLabel.font = DSTheme.titleFont(size: 10)
        [newLabel, learningLabel, reviewLabel].forEach {
            $0.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            $0.textAlignment = .right
            $0.widthAnchor.constraint(equalToConstant: 30).isActive = true
        }
        moreButton.setTitle("•••", for: .normal)
        moreButton.titleLabel?.font = DSTheme.titleFont(size: 13)
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)
        moreButton.accessibilityLabel = "更多操作"

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, filteredLabel])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 6
        let counts = UIStackView(arrangedSubviews: [newLabel, learningLabel, reviewLabel])
        counts.axis = .horizontal
        counts.spacing = 2
        counts.alignment = .center
        [disclosureButton, accentView, titleStack, counts, moreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        leadingConstraint = disclosureButton.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: 10
        )
        NSLayoutConstraint.activate([
            leadingConstraint,
            disclosureButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 26),
            disclosureButton.heightAnchor.constraint(equalToConstant: 36),
            accentView.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 1),
            accentView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accentView.widthAnchor.constraint(equalToConstant: 4),
            accentView.heightAnchor.constraint(equalToConstant: 18),
            titleStack.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 8),
            titleStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            counts.leadingAnchor.constraint(greaterThanOrEqualTo: titleStack.trailingAnchor, constant: 6),
            counts.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.leadingAnchor.constraint(equalTo: counts.trailingAnchor, constant: 2),
            moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 38),
            moreButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        applyTheme()
    }
}
