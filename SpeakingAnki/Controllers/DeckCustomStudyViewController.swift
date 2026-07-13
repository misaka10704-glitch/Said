import UIKit

final class DeckCustomStudyViewController: UIViewController, ThemeRefreshable,
    UITableViewDataSource, UITableViewDelegate {

    private let deck: DeckManagementNode
    private let provider: DeckManagementDataProviding
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let modeControl = UISegmentedControl(items: ["新卡", "复习", "遗忘", "提前", "预习", "筛选"])
    private let valueTitleLabel = UILabel()
    private let valueField = UITextField()
    private let availabilityLabel = UILabel()
    private let cramKindControl = UISegmentedControl(items: ["到期", "新卡", "复习", "全部"])
    private let tagTitleLabel = UILabel()
    private let tagTableView = UITableView(frame: .zero, style: .plain)
    private let cramCard = UIView()
    private let startButton = DSButton(style: .primary)
    private let activityIndicator = UIActivityIndicatorView(style: .gray)
    private var tagHeightConstraint: NSLayoutConstraint!
    private var defaults: DeckCustomStudyDefaults?
    private var tags: [DeckCustomStudyTag] = []
    private var cards: [UIView] = []

    init(deck: DeckManagementNode, provider: DeckManagementDataProviding) {
        self.deck = deck
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "自定义学习"
        configureViews()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .saidThemeDidChange,
            object: nil
        )
        loadDefaults()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applyTheme() {
        let colors = DSTheme.c
        view.backgroundColor = colors.background
        scrollView.backgroundColor = colors.background
        cards.forEach {
            $0.backgroundColor = colors.surface
            $0.layer.borderColor = colors.border.cgColor
        }
        [valueTitleLabel, tagTitleLabel].forEach { $0.textColor = colors.textPrimary }
        availabilityLabel.textColor = colors.textSecondary
        valueField.textColor = colors.textPrimary
        valueField.backgroundColor = colors.inputBackground
        valueField.layer.borderColor = colors.inputBorder.cgColor
        valueField.keyboardAppearance = ThemeManager.shared.mode == .dark ? .dark : .light
        modeControl.tintColor = colors.accent
        cramKindControl.tintColor = colors.accent
        tagTableView.backgroundColor = colors.surface
        tagTableView.separatorColor = colors.divider
        activityIndicator.color = colors.accent
        startButton.applyTheme()
        tagTableView.reloadData()
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func configureViews() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let deckLabel = UILabel()
        deckLabel.text = deck.name
        deckLabel.font = DSTheme.titleFont(size: 18)
        deckLabel.numberOfLines = 0
        deckLabel.textColor = DSTheme.c.textPrimary
        contentStack.addArrangedSubview(deckLabel)

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        contentStack.addArrangedSubview(makeCard(containing: modeControl))

        valueTitleLabel.font = DSTheme.titleFont(size: 15)
        availabilityLabel.font = DSTheme.bodyFont(size: 12)
        availabilityLabel.numberOfLines = 0
        configureNumberField()
        let valueRow = UIStackView(arrangedSubviews: [valueTitleLabel, valueField])
        valueRow.axis = .horizontal
        valueRow.alignment = .center
        valueRow.spacing = 12
        let valueStack = UIStackView(arrangedSubviews: [valueRow, availabilityLabel])
        valueStack.axis = .vertical
        valueStack.spacing = 8
        contentStack.addArrangedSubview(makeCard(containing: valueStack))

        cramKindControl.selectedSegmentIndex = 0
        let cramStack = UIStackView(arrangedSubviews: [
            labeled("筛选卡片类型", control: cramKindControl),
            tagTitleLabel,
            tagTableView
        ])
        cramStack.axis = .vertical
        cramStack.spacing = 10
        tagTitleLabel.text = "标签（轻点循环：不限 → 包含 → 排除）"
        tagTitleLabel.font = DSTheme.bodyFont(size: 13)
        tagTableView.dataSource = self
        tagTableView.delegate = self
        tagTableView.rowHeight = 38
        tagTableView.isScrollEnabled = false
        tagTableView.layer.cornerRadius = 8
        tagHeightConstraint = tagTableView.heightAnchor.constraint(equalToConstant: 0)
        tagHeightConstraint.isActive = true
        configureCard(cramCard, containing: cramStack)
        contentStack.addArrangedSubview(cramCard)

        startButton.setTitle("开始自定义学习", for: .normal)
        startButton.addTarget(self, action: #selector(startStudy), for: .touchUpInside)
        startButton.isEnabled = false
        contentStack.addArrangedSubview(startButton)
        activityIndicator.hidesWhenStopped = true
        contentStack.addArrangedSubview(activityIndicator)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])
        modeChanged()
    }

    private func loadDefaults() {
        activityIndicator.startAnimating()
        provider.loadCustomStudyDefaults(deckID: deck.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                switch result {
                case .success(let value):
                    self.defaults = value
                    self.tags = value.tags
                    self.tagHeightConstraint.constant = CGFloat(min(value.tags.count, 8)) * 38
                    self.tagTableView.isScrollEnabled = value.tags.count > 8
                    self.tagTableView.reloadData()
                    self.startButton.isEnabled = true
                    self.modeChanged()
                case .failure(let error):
                    self.showAlert(error.localizedDescription)
                }
            }
        }
    }

    @objc private func modeChanged() {
        let mode = modeControl.selectedSegmentIndex
        cramCard.isHidden = mode != 5
        let value = defaults
        switch mode {
        case 0:
            valueTitleLabel.text = "增加今天的新卡上限"
            availabilityLabel.text = "当前可用：\(value?.availableNew ?? 0)；含子牌组：\(value?.availableNewInChildren ?? 0)"
            valueField.text = "\(value?.extendNew ?? 10)"
        case 1:
            valueTitleLabel.text = "增加今天的复习上限"
            availabilityLabel.text = "当前可用：\(value?.availableReview ?? 0)；含子牌组：\(value?.availableReviewInChildren ?? 0)"
            valueField.text = "\(value?.extendReview ?? 50)"
        case 2:
            valueTitleLabel.text = "复习最近几天遗忘的卡片"
            availabilityLabel.text = "输入天数"
            valueField.text = "1"
        case 3:
            valueTitleLabel.text = "提前复习未来几天的卡片"
            availabilityLabel.text = "输入天数"
            valueField.text = "1"
        case 4:
            valueTitleLabel.text = "预习未来几天的新卡"
            availabilityLabel.text = "输入天数"
            valueField.text = "1"
        default:
            valueTitleLabel.text = "筛选牌组的卡片上限"
            availabilityLabel.text = "可按类型和标签限制临时学习牌组"
            valueField.text = "100"
        }
    }

    @objc private func startStudy() {
        guard let raw = valueField.text, let number = Int64(raw), number > 0 else {
            showAlert("请输入大于 0 的整数。")
            return
        }
        let action: DeckCustomStudyAction
        switch modeControl.selectedSegmentIndex {
        case 0:
            guard number <= Int64(Int32.max) else {
                showAlert("数值过大。")
                return
            }
            action = .increaseNewLimit(Int32(number))
        case 1:
            guard number <= Int64(Int32.max) else {
                showAlert("数值过大。")
                return
            }
            action = .increaseReviewLimit(Int32(number))
        case 2:
            guard number <= Int64(UInt32.max) else {
                showAlert("数值过大。")
                return
            }
            action = .forgotten(days: UInt32(number))
        case 3:
            guard number <= Int64(UInt32.max) else {
                showAlert("数值过大。")
                return
            }
            action = .reviewAhead(days: UInt32(number))
        case 4:
            guard number <= Int64(UInt32.max) else {
                showAlert("数值过大。")
                return
            }
            action = .previewNew(days: UInt32(number))
        default:
            guard number <= Int64(UInt32.max) else {
                showAlert("数值过大。")
                return
            }
            let kinds: [DeckCustomStudyCramKind] = [.due, .newCards, .review, .all]
            action = .cram(
                kind: kinds[cramKindControl.selectedSegmentIndex],
                cardLimit: UInt32(number),
                includeTags: tags.filter(\.included).map(\.name),
                excludeTags: tags.filter(\.excluded).map(\.name)
            )
        }
        setWorking(true)
        provider.startCustomStudy(deckID: deck.id, action: action) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setWorking(false)
                switch result {
                case .success:
                    let alert = UIAlertController(
                        title: "自定义学习已准备好",
                        message: "牌组列表会显示最新状态。",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "完成", style: .default) { [weak self] _ in
                        self?.navigationController?.popViewController(animated: true)
                    })
                    self.present(alert, animated: true)
                case .failure(let error):
                    self.showAlert(error.localizedDescription)
                }
            }
        }
    }

    private func setWorking(_ working: Bool) {
        startButton.isEnabled = !working
        modeControl.isEnabled = !working
        if working {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tags.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "TagCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
        let tag = tags[indexPath.row]
        cell.backgroundColor = DSTheme.c.surface
        cell.textLabel?.text = tag.name
        cell.textLabel?.textColor = DSTheme.c.textPrimary
        cell.detailTextLabel?.text = tag.included ? "包含" : (tag.excluded ? "排除" : "不限")
        cell.detailTextLabel?.textColor = tag.included
            ? DSTheme.c.success
            : (tag.excluded ? DSTheme.c.destructive : DSTheme.c.textTertiary)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let old = tags[indexPath.row]
        if !old.included && !old.excluded {
            tags[indexPath.row] = DeckCustomStudyTag(name: old.name, included: true, excluded: false)
        } else if old.included {
            tags[indexPath.row] = DeckCustomStudyTag(name: old.name, included: false, excluded: true)
        } else {
            tags[indexPath.row] = DeckCustomStudyTag(name: old.name, included: false, excluded: false)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func configureNumberField() {
        valueField.keyboardType = .numberPad
        valueField.textAlignment = .right
        valueField.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        valueField.layer.borderWidth = 1
        valueField.layer.cornerRadius = 8
        valueField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        valueField.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func labeled(_ title: String, control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = DSTheme.bodyFont(size: 13)
        label.textColor = DSTheme.c.textSecondary
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 7
        return stack
    }

    private func makeCard(containing content: UIView) -> UIView {
        let card = UIView()
        configureCard(card, containing: content)
        return card
    }

    private func configureCard(_ card: UIView, containing content: UIView) {
        card.layer.borderWidth = 1
        card.layer.cornerRadius = DSTheme.Form.cornerRadius
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        cards.append(card)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
