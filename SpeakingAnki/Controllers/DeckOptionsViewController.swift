import UIKit

final class DeckOptionsViewController: UIViewController, ThemeRefreshable {
  private let deckID: Int64
  private let provider: DeckOptionsDataProviding
  private let scrollView = UIScrollView()
  private let contentStack = UIStackView()
  private let retentionSlider = UISlider()
  private let retentionValueLabel = UILabel()
  private let newLimitField = UITextField()
  private let reviewLimitField = UITextField()
  private let buryNewSwitch = UISwitch()
  private let buryReviewSwitch = UISwitch()
  private let buryLearningSwitch = UISwitch()
  private let activityIndicator = UIActivityIndicatorView(style: .gray)
  private var options: DeckOptions?
  private var sections: [DSFormSection] = []
  private var primaryLabels: [UILabel] = []
  private var secondaryLabels: [UILabel] = []
  private var tertiaryLabels: [UILabel] = []
  private var separators: [UIView] = []

  init(deckID: Int64, provider: DeckOptionsDataProviding) {
    self.deckID = deckID
    self.provider = provider
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "牌组选项"
    configureViews()
    applyTheme()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
    loadOptions()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureViews() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "保存",
      style: .done,
      target: self,
      action: #selector(save)
    )
    navigationItem.rightBarButtonItem?.isEnabled = false

    scrollView.alwaysBounceVertical = true
    scrollView.keyboardDismissMode = .interactive
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.spacing = 12
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    let retentionSection = makeSection("FSRS")
    let retentionCard = retentionSection.content.stackView
    let retentionTitle = UILabel()
    retentionTitle.text = "期望记忆率"
    retentionTitle.font = DSTheme.titleFont(size: 15)
    primaryLabels.append(retentionTitle)
    retentionValueLabel.font = DSTheme.titleFont(size: 15)
    retentionValueLabel.textAlignment = .right
    let retentionHeader = UIStackView(arrangedSubviews: [retentionTitle, retentionValueLabel])
    retentionHeader.distribution = .fillEqually
    retentionSlider.minimumValue = 0.70
    retentionSlider.maximumValue = 0.99
    retentionSlider.addTarget(self, action: #selector(retentionChanged), for: .valueChanged)
    retentionCard.addArrangedSubview(retentionHeader)
    retentionCard.addArrangedSubview(retentionSlider)
    let retentionHint = hintLabel("记忆率越高，安排的复习越多。常用范围为 85%–95%。")
    retentionCard.addArrangedSubview(retentionHint)
    contentStack.addArrangedSubview(retentionSection)

    let limitsSection = makeSection("每日限额")
    let limitsCard = limitsSection.content.stackView
    configureNumberField(newLimitField, placeholder: "20")
    configureNumberField(reviewLimitField, placeholder: "200")
    limitsCard.addArrangedSubview(makeValueRow(title: "每天新卡片数", control: newLimitField))
    limitsCard.addArrangedSubview(separator())
    limitsCard.addArrangedSubview(makeValueRow(title: "每天最大复习数", control: reviewLimitField))
    contentStack.addArrangedSubview(limitsSection)

    let burySection = makeSection(
      "搁置关联卡片",
      detail: "避免同一笔记生成的关联卡片在同一天连续出现。"
    )
    let buryCard = burySection.content.stackView
    buryCard.addArrangedSubview(makeValueRow(title: "搁置新卡关联卡", control: buryNewSwitch))
    buryCard.addArrangedSubview(separator())
    buryCard.addArrangedSubview(makeValueRow(title: "搁置复习关联卡", control: buryReviewSwitch))
    buryCard.addArrangedSubview(separator())
    buryCard.addArrangedSubview(makeValueRow(title: "搁置跨日学习关联卡", control: buryLearningSwitch))
    contentStack.addArrangedSubview(burySection)

    activityIndicator.hidesWhenStopped = true
    contentStack.addArrangedSubview(activityIndicator)

    view.addSubview(scrollView)
    scrollView.addSubview(contentStack)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      contentStack.topAnchor.constraint(
        equalTo: scrollView.topAnchor, constant: DSTheme.contentPadding),
      contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: scrollView.leadingAnchor, constant: DSTheme.contentPadding),
      contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: scrollView.trailingAnchor, constant: -DSTheme.contentPadding),
      contentStack.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      contentStack.bottomAnchor.constraint(
        equalTo: scrollView.bottomAnchor, constant: -DSTheme.contentPadding),
      contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      contentStack.widthAnchor.constraint(
        equalTo: scrollView.widthAnchor, constant: -DSTheme.contentPadding * 2
      ).withPriority(750),
    ])
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    scrollView.backgroundColor = colors.background
    retentionSlider.tintColor = colors.accent
    retentionValueLabel.textColor = colors.accent
    for control in [buryNewSwitch, buryReviewSwitch, buryLearningSwitch] {
      control.onTintColor = colors.accent
    }
    for section in sections { section.applyTheme() }
    for label in primaryLabels { label.textColor = colors.textPrimary }
    for label in secondaryLabels { label.textColor = colors.textSecondary }
    for label in tertiaryLabels { label.textColor = colors.textTertiary }
    for separator in separators { separator.backgroundColor = colors.divider }
    for field in [newLimitField, reviewLimitField] {
      field.textColor = colors.textPrimary
      field.backgroundColor = colors.inputBackground
      field.layer.borderColor = colors.inputBorder.cgColor
      field.keyboardAppearance = ThemeManager.shared.mode == .dark ? .dark : .light
    }
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  private func loadOptions() {
    activityIndicator.startAnimating()
    provider.loadOptions(deckID: deckID) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.activityIndicator.stopAnimating()
        switch result {
        case .success(let options):
          self.options = options
          self.title = options.deckName
          self.retentionSlider.value = Float(options.desiredRetention)
          self.newLimitField.text = "\(options.newCardsPerDay)"
          self.reviewLimitField.text = "\(options.reviewsPerDay)"
          self.buryNewSwitch.isOn = options.buryNewSiblings
          self.buryReviewSwitch.isOn = options.buryReviewSiblings
          self.buryLearningSwitch.isOn = options.buryInterdayLearningSiblings
          self.retentionChanged()
          self.navigationItem.rightBarButtonItem?.isEnabled = true
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  @objc private func retentionChanged() {
    retentionValueLabel.text = String(format: "%.0f%%", retentionSlider.value * 100)
  }

  @objc private func save() {
    guard var updated = options else { return }
    guard let newLimit = Int(newLimitField.text ?? ""), newLimit >= 0,
      let reviewLimit = Int(reviewLimitField.text ?? ""), reviewLimit >= 0
    else {
      showAlert("每日限额必须是大于或等于零的整数。")
      return
    }
    updated.desiredRetention = Double(retentionSlider.value)
    updated.newCardsPerDay = newLimit
    updated.reviewsPerDay = reviewLimit
    updated.buryNewSiblings = buryNewSwitch.isOn
    updated.buryReviewSiblings = buryReviewSwitch.isOn
    updated.buryInterdayLearningSiblings = buryLearningSwitch.isOn

    activityIndicator.startAnimating()
    navigationItem.rightBarButtonItem?.isEnabled = false
    provider.saveOptions(updated) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.activityIndicator.stopAnimating()
        self.navigationItem.rightBarButtonItem?.isEnabled = true
        switch result {
        case .success:
          self.options = updated
          self.navigationController?.popViewController(animated: true)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  private func makeSection(_ title: String, detail: String? = nil) -> DSFormSection {
    let section = DSFormSection(title: title, detail: detail)
    sections.append(section)
    return section
  }

  private func hintLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DSTheme.bodyFont(size: 12)
    label.textColor = DSTheme.c.textTertiary
    label.numberOfLines = 0
    tertiaryLabels.append(label)
    return label
  }

  private func configureNumberField(_ field: UITextField, placeholder: String) {
    field.keyboardType = .numberPad
    field.textAlignment = .right
    field.placeholder = placeholder
    field.font = DSTheme.bodyFont(size: 16)
    field.textColor = DSTheme.c.textPrimary
    field.backgroundColor = DSTheme.c.inputBackground
    field.layer.borderColor = DSTheme.c.inputBorder.cgColor
    field.layer.borderWidth = 1
    field.layer.cornerRadius = 8
    field.widthAnchor.constraint(equalToConstant: 110).isActive = true
    field.heightAnchor.constraint(equalToConstant: 36).isActive = true
  }

  private func makeValueRow(title: String, control: UIView) -> UIStackView {
    let label = UILabel()
    label.text = title
    label.font = DSTheme.bodyFont(size: 15)
    label.textColor = DSTheme.c.textPrimary
    label.numberOfLines = 0
    primaryLabels.append(label)
    let row = UIStackView(arrangedSubviews: [label, control])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = 12
    return row
  }

  private func separator() -> UIView {
    let line = UIView()
    line.backgroundColor = DSTheme.c.divider
    line.heightAnchor.constraint(equalToConstant: DSTheme.List.separatorHeight).isActive = true
    separators.append(line)
    return line
  }

  private func showAlert(_ message: String) {
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }
}
