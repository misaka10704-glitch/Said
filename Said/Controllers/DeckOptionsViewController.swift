import UIKit
import SaidAnkiBackend

final class DeckOptionsViewController: UIViewController, ThemeRefreshable {
  private enum LimitScope: Int { case preset, deck, today }

  private let deckID: Int64
  private let provider: DeckOptionsDataProviding
  private let scrollView = UIScrollView()
  private let contentStack = UIStackView()
  private var contentMaxWidthConstraint: NSLayoutConstraint?
  private let metadataLabel = UILabel()
  private let selectPresetButton = DSButton(style: .secondary)
  private let newPresetButton = DSButton(style: .secondary)
  private let fsrsStatusLabel = UILabel()
  private let retentionSlider = UISlider()
  private let retentionValueLabel = UILabel()
  private let historicalRetentionField = UITextField()
  private let limitScope = UISegmentedControl(items: ["预设", "本牌组", "仅今天"])
  private let newLimitField = UITextField()
  private let reviewLimitField = UITextField()
  private let effectiveLimitsLabel = UILabel()
  private let learnStepsField = UITextField()
  private let goodIntervalField = UITextField()
  private let easyIntervalField = UITextField()
  private let relearnStepsField = UITextField()
  private let minimumLapseField = UITextField()
  private let leechThresholdField = UITextField()
  private let maximumReviewField = UITextField()
  private let leechActionControl = UISegmentedControl(items: ["暂停", "仅标记"])
  private let insertOrderButton = UIButton(type: .system)
  private let gatherOrderButton = UIButton(type: .system)
  private let sortOrderButton = UIButton(type: .system)
  private let newMixControl = UISegmentedControl(items: ["混合", "复习后", "复习前"])
  private let interdayMixControl = UISegmentedControl(items: ["混合", "复习后", "复习前"])
  private let reviewOrderButton = UIButton(type: .system)
  private let buryNewSwitch = UISwitch()
  private let buryReviewSwitch = UISwitch()
  private let buryLearningSwitch = UISwitch()
  private let curtainSwitch = UISwitch()
  private let centerSentenceSwitch = UISwitch()
  private let sentenceSizeSlider = UISlider()
  private let sentenceSizeValueLabel = UILabel()
  private let cardTemplateButton = DSButton(style: .secondary)
  private let activityIndicator = DSTheme.makeActivityIndicator()
  private var options: DeckOptions?
  private var sections: [DSFormSection] = []
  private var primaryLabels: [UILabel] = []
  private var tertiaryLabels: [UILabel] = []
  private var separators: [UIView] = []
  private var choiceValues: [ObjectIdentifier: Int] = [:]
  private var isApplyingOptions = false
  private var isDirty = false
  private var presetIsDirty = false
  private var displayedLimitScope: LimitScope = .preset

  private let insertChoices = [("按位置", 0), ("随机", 1)]
  private let gatherChoices = [
    ("牌组顺序", 0), ("牌组后随机笔记", 5), ("位置升序", 1),
    ("位置降序", 2), ("随机笔记", 3), ("随机卡片", 4),
  ]
  private let sortChoices = [
    ("卡片模板", 0), ("不排序", 1), ("模板后随机", 2),
    ("随机笔记后模板", 3), ("随机卡片", 4),
  ]
  private let reviewChoices = [
    ("到期日", 0), ("到期日后牌组", 1), ("牌组后到期日", 2),
    ("间隔升序", 3), ("间隔降序", 4), ("难度升序", 5),
    ("难度降序", 6), ("可提取性升序", 7), ("随机", 8),
    ("添加顺序", 9), ("添加逆序", 10), ("可提取性降序", 11),
  ]

  init(deckID: Int64, provider: DeckOptionsDataProviding) {
    self.deckID = deckID
    self.provider = provider
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "牌组选项"
    configureViews()
    applyTheme()
    NotificationCenter.default.addObserver(
      self, selector: #selector(themeDidChange), name: .saidThemeDidChange, object: nil)
    loadOptions()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  private func configureViews() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "保存", style: .done, target: self, action: #selector(save))
    navigationItem.rightBarButtonItem?.isEnabled = false
    scrollView.alwaysBounceVertical = true
    scrollView.keyboardDismissMode = .interactive
    // The scroll view already starts below the navigation bar via safeArea.
    // Automatic adjustment applies that inset a second time and initially
    // shifts the first section title beneath the bar.
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.spacing = 12
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    metadataLabel.numberOfLines = 0
    metadataLabel.font = DSTheme.bodyFont(size: 14)
    primaryLabels.append(metadataLabel)
    let presetSection = makeSection("预设")
    presetSection.content.stackView.addArrangedSubview(metadataLabel)
    let presetActions = UIStackView(arrangedSubviews: [selectPresetButton, newPresetButton])
    presetActions.axis = .horizontal
    presetActions.spacing = 8
    presetActions.distribution = .fillEqually
    selectPresetButton.setTitle("选择预设", for: .normal)
    selectPresetButton.addTarget(self, action: #selector(selectPreset), for: .touchUpInside)
    newPresetButton.setTitle("新建预设", for: .normal)
    newPresetButton.addTarget(self, action: #selector(createPreset), for: .touchUpInside)
    presetSection.content.stackView.addArrangedSubview(presetActions)
    contentStack.addArrangedSubview(presetSection)

    let practiceSection = makeSection(
      "Said 口语设置",
      detail: "仅应用于当前牌组，不会改变 Anki 的排程预设。"
    )
    configurePracticePreferences()
    practiceSection.content.stackView.addArrangedSubview(
      labeledControlRow(title: "默认黑幕", control: curtainSwitch))
    practiceSection.content.stackView.addArrangedSubview(separator())
    practiceSection.content.stackView.addArrangedSubview(
      labeledControlRow(title: "正面句子居中", control: centerSentenceSwitch))
    practiceSection.content.stackView.addArrangedSubview(separator())
    sentenceSizeValueLabel.font = DSTheme.bodyFont(size: 14)
    sentenceSizeValueLabel.textAlignment = .right
    primaryLabels.append(sentenceSizeValueLabel)
    let sentenceSizeHeader = UIStackView(arrangedSubviews: [
      makeRowTitle("正面句子字号"), sentenceSizeValueLabel
    ])
    sentenceSizeHeader.axis = .horizontal
    sentenceSizeHeader.alignment = .center
    practiceSection.content.stackView.addArrangedSubview(sentenceSizeHeader)
    practiceSection.content.stackView.addArrangedSubview(sentenceSizeSlider)
    practiceSection.content.stackView.addArrangedSubview(separator())
    cardTemplateButton.addTarget(self, action: #selector(selectCardTemplate), for: .touchUpInside)
    practiceSection.content.stackView.addArrangedSubview(cardTemplateButton)
    let addCardButton = DSButton(style: .primary)
    addCardButton.setTitle("添加卡片", for: .normal)
    addCardButton.addTarget(self, action: #selector(openAddCard), for: .touchUpInside)
    practiceSection.content.stackView.addArrangedSubview(addCardButton)
    contentStack.addArrangedSubview(practiceSection)

    let fsrsSection = makeSection("FSRS 与记忆模型")
    fsrsStatusLabel.font = DSTheme.bodyFont(size: 14)
    primaryLabels.append(fsrsStatusLabel)
    fsrsSection.content.stackView.addArrangedSubview(fsrsStatusLabel)
    fsrsSection.content.stackView.addArrangedSubview(separator())
    let retentionTitle = UILabel()
    retentionTitle.text = "期望记忆率"
    retentionTitle.font = DSTheme.titleFont(size: 15)
    primaryLabels.append(retentionTitle)
    retentionValueLabel.font = DSTheme.titleFont(size: 15)
    retentionValueLabel.textAlignment = .right
    let retentionHeader = UIStackView(arrangedSubviews: [retentionTitle, retentionValueLabel])
    retentionHeader.axis = .horizontal
    retentionHeader.alignment = .firstBaseline
    retentionHeader.distribution = .fill
    retentionValueLabel.setContentHuggingPriority(.required, for: .horizontal)
    retentionValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    retentionSlider.minimumValue = 0.70
    retentionSlider.maximumValue = 0.99
    retentionSlider.addTarget(self, action: #selector(retentionChanged), for: .valueChanged)
    fsrsSection.content.stackView.addArrangedSubview(retentionHeader)
    fsrsSection.content.stackView.addArrangedSubview(retentionSlider)
    configureDecimalField(historicalRetentionField, placeholder: "0.90")
    fsrsSection.content.stackView.addArrangedSubview(separator())
    fsrsSection.content.stackView.addArrangedSubview(
      numericRow(title: "历史记忆率", field: historicalRetentionField))
    fsrsSection.content.stackView.addArrangedSubview(
      hintLabel("FSRS 关闭时这些值只显示，不会伪装为已启用。期望记忆率保存为本牌组覆盖。"))
    contentStack.addArrangedSubview(fsrsSection)

    let limitsSection = makeSection(
      "每日限额",
      detail: "预设会影响所有使用该预设的牌组；本牌组与仅今天留空时继承预设。"
    )
    limitScope.selectedSegmentIndex = LimitScope.preset.rawValue
    limitScope.addTarget(self, action: #selector(limitScopeChanged), for: .valueChanged)
    limitsSection.content.stackView.addArrangedSubview(limitScope)
    configureNumberField(newLimitField, placeholder: "继承")
    configureNumberField(reviewLimitField, placeholder: "继承")
    limitsSection.content.stackView.addArrangedSubview(
      numericRow(title: "每天新卡片数", field: newLimitField))
    limitsSection.content.stackView.addArrangedSubview(separator())
    limitsSection.content.stackView.addArrangedSubview(
      numericRow(title: "每天最大复习数", field: reviewLimitField))
    effectiveLimitsLabel.numberOfLines = 0
    effectiveLimitsLabel.font = DSTheme.bodyFont(size: 12)
    tertiaryLabels.append(effectiveLimitsLabel)
    limitsSection.content.stackView.addArrangedSubview(effectiveLimitsLabel)
    contentStack.addArrangedSubview(limitsSection)

    let learningSection = makeSection("新卡与学习（预设）")
    configureStepsField(learnStepsField, placeholder: "1 10")
    configureNumberField(goodIntervalField, placeholder: "1")
    configureNumberField(easyIntervalField, placeholder: "4")
    addRows([
      ("学习步骤（分钟）", learnStepsField),
      ("良好毕业间隔（天）", goodIntervalField),
      ("简单毕业间隔（天）", easyIntervalField),
    ], to: learningSection.content.stackView)
    contentStack.addArrangedSubview(learningSection)

    let lapseSection = makeSection("失误与水蛭（预设）")
    configureStepsField(relearnStepsField, placeholder: "10")
    configureNumberField(minimumLapseField, placeholder: "1")
    configureNumberField(leechThresholdField, placeholder: "8")
    configureNumberField(maximumReviewField, placeholder: "36500")
    leechActionControl.selectedSegmentIndex = 0
    leechActionControl.addTarget(self, action: #selector(presetControlChanged), for: .valueChanged)
    addRows([
      ("重学步骤（分钟）", relearnStepsField),
      ("最小失误间隔（天）", minimumLapseField),
      ("水蛭阈值", leechThresholdField),
      ("水蛭动作", leechActionControl),
      ("最大复习间隔（天）", maximumReviewField),
    ], to: lapseSection.content.stackView)
    contentStack.addArrangedSubview(lapseSection)

    let orderSection = makeSection("显示顺序（预设）")
    configureChoiceButton(insertOrderButton, action: #selector(selectInsertOrder))
    configureChoiceButton(gatherOrderButton, action: #selector(selectGatherOrder))
    configureChoiceButton(sortOrderButton, action: #selector(selectSortOrder))
    configureChoiceButton(reviewOrderButton, action: #selector(selectReviewOrder))
    for control in [newMixControl, interdayMixControl] {
      control.addTarget(self, action: #selector(presetControlChanged), for: .valueChanged)
    }
    addRows([
      ("新卡插入顺序", insertOrderButton),
      ("新卡收集顺序", gatherOrderButton),
      ("新卡排序", sortOrderButton),
      ("新卡与复习", newMixControl),
      ("跨日学习与复习", interdayMixControl),
      ("复习排序", reviewOrderButton),
    ], to: orderSection.content.stackView)
    contentStack.addArrangedSubview(orderSection)

    let burySection = makeSection("搁置关联卡片（预设）")
    addRows([
      ("搁置新卡关联卡", buryNewSwitch),
      ("搁置复习关联卡", buryReviewSwitch),
      ("搁置跨日学习关联卡", buryLearningSwitch),
    ], to: burySection.content.stackView)
    contentStack.addArrangedSubview(burySection)

    // Match Anki Desktop's mental model: schedule settings come first and
    // app-specific study presentation tools live in their own final section.
    contentStack.removeArrangedSubview(practiceSection)
    practiceSection.removeFromSuperview()
    contentStack.addArrangedSubview(practiceSection)

    for field in allTextFields {
      field.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
    }
    for control in [buryNewSwitch, buryReviewSwitch, buryLearningSwitch] {
      control.addTarget(self, action: #selector(presetControlChanged), for: .valueChanged)
    }

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
        // Keep the first section label clear of the split-view navigation bar
        // even when UIKit restores an initial negative scroll offset.
        equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DSTheme.contentPadding * 2),
      contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: scrollView.contentLayoutGuide.leadingAnchor,
        constant: DSTheme.contentPadding),
      contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: scrollView.contentLayoutGuide.trailingAnchor,
        constant: -DSTheme.contentPadding),
      contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
      contentStack.bottomAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DSTheme.contentPadding),
      contentStack.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -DSTheme.contentPadding * 2
      ),
    ])
    contentMaxWidthConstraint = contentStack.widthAnchor.constraint(
      lessThanOrEqualToConstant: DSTheme.contentMaxWidth)
    contentMaxWidthConstraint?.isActive = true
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // In a split view the detail pane can be narrower than it is tall even
    // while the device is horizontal, so use the containing window instead.
    let windowBounds = view.window?.bounds ?? UIScreen.main.bounds
    let isLandscape = windowBounds.width > windowBounds.height
    let availableWidth = max(0, view.bounds.width - DSTheme.contentPadding * 2)
    contentMaxWidthConstraint?.constant = isLandscape
      ? availableWidth
      : min(DSTheme.contentMaxWidth, availableWidth)
  }

  @objc private func openAddCard() {
    navigationController?.pushViewController(
      AddSpeakingCardViewController(
        deckID: deckID,
        deckName: options?.deckName ?? "当前牌组"
      ),
      animated: true
    )
  }

  @objc private func selectPreset() {
    guard !isDirty else {
      showAlert("请先保存或放弃当前修改，再切换预设。")
      return
    }
    activityIndicator.startAnimating()
    provider.loadPresets(deckID: deckID) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.activityIndicator.stopAnimating()
        switch result {
        case .success(let presets):
          let sheet = UIAlertController(
            title: "选择预设",
            message: "切换后，当前牌组会使用该预设的学习与排程设置。",
            preferredStyle: .actionSheet
          )
          for preset in presets {
            let suffix = preset.id == self.options?.configID ? "（当前）" : ""
            sheet.addAction(UIAlertAction(
              title: "\(preset.name)\(suffix) · \(preset.useCount) 个牌组",
              style: .default
            ) { _ in
              guard preset.id != self.options?.configID else { return }
              self.assignPreset(preset)
            })
          }
          sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
          sheet.popoverPresentationController?.sourceView = self.selectPresetButton
          sheet.popoverPresentationController?.sourceRect = self.selectPresetButton.bounds
          self.present(sheet, animated: true)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  private func assignPreset(_ preset: SaidDeckPreset) {
    activityIndicator.startAnimating()
    provider.selectPreset(deckID: deckID, presetID: preset.id) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.activityIndicator.stopAnimating()
        switch result {
        case .success:
          self.loadOptions()
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  @objc private func createPreset() {
    guard !isDirty else {
      showAlert("请先保存或放弃当前修改，再新建预设。")
      return
    }
    let alert = UIAlertController(
      title: "新建预设",
      message: "会复制当前预设的全部学习与排程设置，并自动分配给当前牌组。",
      preferredStyle: .alert
    )
    alert.addTextField {
      $0.placeholder = "预设名称"
      $0.clearButtonMode = .whileEditing
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
      guard let self = self else { return }
      let name = alert?.textFields?.first?.text ?? ""
      self.activityIndicator.startAnimating()
      self.provider.clonePreset(deckID: self.deckID, name: name) { [weak self] result in
        DispatchQueue.main.async {
          guard let self = self else { return }
          self.activityIndicator.stopAnimating()
          switch result {
          case .success:
            self.loadOptions()
          case .failure(let error):
            self.showAlert(error.localizedDescription)
          }
        }
      }
    })
    present(alert, animated: true)
  }

  @objc private func selectCardTemplate() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try AnkiStore.shared.requireCollection().allNoteTypes() }
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success(let types):
          let alert = UIAlertController(
            title: "选择卡片模板",
            message: "之后从此牌组添加卡片会直接使用该模板。",
            preferredStyle: .actionSheet
          )
          for type in types {
            alert.addAction(UIAlertAction(title: type.name, style: .default) { _ in
              var preferences = DeckPracticePreferencesStore.shared.preferences(for: self.deckID)
              preferences.noteTypeID = type.id
              DeckPracticePreferencesStore.shared.save(preferences, for: self.deckID)
              self.cardTemplateButton.setTitle("卡片模板：\(type.name)", for: .normal)
            })
          }
          alert.addAction(UIAlertAction(title: "取消", style: .cancel))
          alert.popoverPresentationController?.sourceView = self.view
          alert.popoverPresentationController?.sourceRect = CGRect(
            x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1
          )
          self.present(alert, animated: true)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  private func configurePracticePreferences() {
    let preferences = DeckPracticePreferencesStore.shared.preferences(for: deckID)
    curtainSwitch.isOn = preferences.curtainEnabled
    centerSentenceSwitch.isOn = preferences.centerSentence
    sentenceSizeSlider.minimumValue = 16
    sentenceSizeSlider.maximumValue = 32
    sentenceSizeSlider.value = Float(preferences.sentenceFontSize)
    sentenceSizeValueLabel.text = "\(Int(sentenceSizeSlider.value.rounded())) pt"
    cardTemplateButton.setTitle(
      preferences.noteTypeID == nil ? "选择卡片模板" : "卡片模板：已选择",
      for: .normal
    )
    [curtainSwitch, centerSentenceSwitch].forEach {
      $0.addTarget(self, action: #selector(savePracticePreferences), for: .valueChanged)
    }
    sentenceSizeSlider.addTarget(
      self, action: #selector(savePracticePreferences), for: .valueChanged)
  }

  @objc private func savePracticePreferences() {
    sentenceSizeValueLabel.text = "\(Int(sentenceSizeSlider.value.rounded())) pt"
    var preferences = DeckPracticePreferencesStore.shared.preferences(for: deckID)
    preferences.curtainEnabled = curtainSwitch.isOn
    preferences.centerSentence = centerSentenceSwitch.isOn
    preferences.sentenceFontSize = Double(sentenceSizeSlider.value)
    DeckPracticePreferencesStore.shared.save(preferences, for: deckID)
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    scrollView.backgroundColor = colors.background
    retentionSlider.tintColor = colors.accent
    sentenceSizeSlider.tintColor = colors.accent
    retentionValueLabel.textColor = colors.accent
    for control in [buryNewSwitch, buryReviewSwitch, buryLearningSwitch, curtainSwitch, centerSentenceSwitch] {
      control.onTintColor = colors.accent
    }
    for section in sections { section.applyTheme() }
    for label in primaryLabels { label.textColor = colors.textPrimary }
    for label in tertiaryLabels { label.textColor = colors.textTertiary }
    for separator in separators { separator.backgroundColor = colors.divider }
    for field in allTextFields {
      field.textColor = colors.textPrimary
      field.backgroundColor = colors.inputBackground
      field.layer.borderColor = colors.inputBorder.cgColor
      field.keyboardAppearance = ThemeManager.shared.mode == .dark ? .dark : .light
    }
  }

  @objc private func themeDidChange() { applyTheme() }

  private func loadOptions() {
    activityIndicator.startAnimating()
    provider.loadOptions(deckID: deckID) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.activityIndicator.stopAnimating()
        switch result {
        case .success(let options):
          self.options = options
          self.apply(options)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  private func apply(_ value: DeckOptions) {
    isApplyingOptions = true
    title = "牌组选项"
    navigationItem.prompt = value.deckName
    metadataLabel.text =
      "当前使用“\(value.presetName)”预设"
      + (value.presetUseCount > 1
        ? " · 与另外 \(value.presetUseCount - 1) 个牌组共享"
        : " · 仅此牌组使用")
    fsrsStatusLabel.text = value.fsrsEnabled ? "FSRS：已启用" : "FSRS：未启用"
    retentionSlider.value = Float(value.desiredRetention)
    retentionSlider.isEnabled = value.fsrsEnabled
    historicalRetentionField.text = formatDecimal(value.historicalRetention)
    historicalRetentionField.isEnabled = value.fsrsEnabled
    learnStepsField.text = formatSteps(value.learnSteps)
    goodIntervalField.text = "\(value.graduatingIntervalGood)"
    easyIntervalField.text = "\(value.graduatingIntervalEasy)"
    relearnStepsField.text = formatSteps(value.relearnSteps)
    minimumLapseField.text = "\(value.minimumLapseInterval)"
    leechThresholdField.text = "\(value.leechThreshold)"
    leechActionControl.selectedSegmentIndex = value.leechAction == 1 ? 1 : 0
    maximumReviewField.text = "\(value.maximumReviewInterval)"
    setChoice(insertOrderButton, value: value.newCardInsertOrder, choices: insertChoices)
    setChoice(gatherOrderButton, value: value.newCardGatherPriority, choices: gatherChoices)
    setChoice(sortOrderButton, value: value.newCardSortOrder, choices: sortChoices)
    newMixControl.selectedSegmentIndex = (0...2).contains(value.newMix) ? value.newMix : -1
    interdayMixControl.selectedSegmentIndex =
      (0...2).contains(value.interdayLearningMix) ? value.interdayLearningMix : -1
    setChoice(reviewOrderButton, value: value.reviewOrder, choices: reviewChoices)
    buryNewSwitch.isOn = value.buryNewSiblings
    buryReviewSwitch.isOn = value.buryReviewSiblings
    buryLearningSwitch.isOn = value.buryInterdayLearningSiblings
    retentionChanged()
    displayedLimitScope = .preset
    limitScope.selectedSegmentIndex = displayedLimitScope.rawValue
    displayLimits(for: value)
    isApplyingOptions = false
    isDirty = false
    presetIsDirty = false
    navigationItem.rightBarButtonItem?.isEnabled = false
  }

  @objc private func retentionChanged() {
    retentionValueLabel.text = String(format: "%.0f%%", retentionSlider.value * 100)
    if !isApplyingOptions {
      options?.desiredRetentionIsOverride = true
    }
    markDirty(preset: false)
  }

  @objc private func limitScopeChanged() {
    guard var value = options else { return }
    let requested = LimitScope(rawValue: limitScope.selectedSegmentIndex) ?? .preset
    guard commitLimitFields(scope: displayedLimitScope, to: &value, showError: true) else {
      limitScope.selectedSegmentIndex = displayedLimitScope.rawValue
      return
    }
    options = value
    displayedLimitScope = requested
    displayLimits(for: value)
  }

  private func displayLimits(for value: DeckOptions) {
    switch LimitScope(rawValue: limitScope.selectedSegmentIndex) ?? .preset {
    case .preset:
      newLimitField.text = "\(value.presetNewCardsPerDay)"
      reviewLimitField.text = "\(value.presetReviewsPerDay)"
      newLimitField.placeholder = nil
      reviewLimitField.placeholder = nil
    case .deck:
      newLimitField.text = value.deckNewCardsPerDay.map(String.init) ?? ""
      reviewLimitField.text = value.deckReviewsPerDay.map(String.init) ?? ""
      newLimitField.placeholder = "继承"
      reviewLimitField.placeholder = "继承"
    case .today:
      newLimitField.text = value.todayNewCardsPerDay.map(String.init) ?? ""
      reviewLimitField.text = value.todayReviewsPerDay.map(String.init) ?? ""
      newLimitField.placeholder = "继承"
      reviewLimitField.placeholder = "继承"
    }
    effectiveLimitsLabel.text =
      "实际生效：新卡 \(value.effectiveNewCardsPerDay) / 复习 \(value.effectiveReviewsPerDay)"
      + "（父牌组上限仍可能进一步限制）"
  }

  @objc private func textFieldChanged(_ sender: UITextField) {
    if sender === newLimitField || sender === reviewLimitField {
      updateLimitDraft()
    }
    let isPresetLimit = (sender === newLimitField || sender === reviewLimitField)
      && limitScope.selectedSegmentIndex == LimitScope.preset.rawValue
    let isDeckRetention = sender === historicalRetentionField && options?.fsrsEnabled != true
    markDirty(preset: !isDeckRetention && (isPresetLimit || isPresetField(sender)))
  }

  private func updateLimitDraft() {
    guard var value = options else { return }
    guard commitLimitFields(scope: displayedLimitScope, to: &value, showError: false) else { return }
    options = value
    effectiveLimitsLabel.text =
      "实际生效：新卡 \(value.effectiveNewCardsPerDay) / 复习 \(value.effectiveReviewsPerDay)"
  }

  @objc private func presetControlChanged() { markDirty(preset: true) }

  private func markDirty(preset: Bool) {
    guard !isApplyingOptions, options != nil else { return }
    isDirty = true
    presetIsDirty = presetIsDirty || preset
    navigationItem.rightBarButtonItem?.isEnabled = true
  }

  @objc private func save() {
    guard isDirty, let updated = validatedOptions() else { return }
    if presetIsDirty, updated.presetUseCount > 1 {
      let alert = UIAlertController(
        title: "保存共享预设？",
        message: "“\(updated.presetName)”被 \(updated.presetUseCount) 个牌组使用。预设字段的更改会影响所有使用它的牌组。",
        preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "取消", style: .cancel))
      alert.addAction(UIAlertAction(title: "仍要保存", style: .destructive) { [weak self] _ in
        self?.performSave(updated)
      })
      present(alert, animated: true)
    } else {
      performSave(updated)
    }
  }

  private func validatedOptions() -> DeckOptions? {
    guard var updated = options else { return nil }
    guard commitVisibleLimits(to: &updated) else { return nil }
    guard let learnSteps = parseSteps(learnStepsField.text, allowEmpty: false),
      let relearnSteps = parseSteps(relearnStepsField.text, allowEmpty: true),
      let good = positiveInt(goodIntervalField, name: "良好毕业间隔"),
      let easy = positiveInt(easyIntervalField, name: "简单毕业间隔"),
      let minimum = nonnegativeInt(minimumLapseField, name: "最小失误间隔"),
      let leech = positiveInt(leechThresholdField, name: "水蛭阈值"),
      let maximum = positiveInt(maximumReviewField, name: "最大复习间隔")
    else { return nil }
    if good > easy {
      showAlert("简单毕业间隔不能小于良好毕业间隔。")
      return nil
    }
    if minimum > maximum {
      showAlert("最小失误间隔不能大于最大复习间隔。")
      return nil
    }
    updated.learnSteps = learnSteps
    updated.graduatingIntervalGood = good
    updated.graduatingIntervalEasy = easy
    updated.relearnSteps = relearnSteps
    updated.minimumLapseInterval = minimum
    updated.leechThreshold = leech
    updated.maximumReviewInterval = maximum
    updated.leechAction = leechActionControl.selectedSegmentIndex
    updated.newCardInsertOrder = choiceValues[ObjectIdentifier(insertOrderButton)]
      ?? updated.newCardInsertOrder
    updated.newCardGatherPriority = choiceValues[ObjectIdentifier(gatherOrderButton)]
      ?? updated.newCardGatherPriority
    updated.newCardSortOrder = choiceValues[ObjectIdentifier(sortOrderButton)]
      ?? updated.newCardSortOrder
    if newMixControl.selectedSegmentIndex >= 0 {
      updated.newMix = newMixControl.selectedSegmentIndex
    }
    if interdayMixControl.selectedSegmentIndex >= 0 {
      updated.interdayLearningMix = interdayMixControl.selectedSegmentIndex
    }
    updated.reviewOrder = choiceValues[ObjectIdentifier(reviewOrderButton)] ?? updated.reviewOrder
    updated.buryNewSiblings = buryNewSwitch.isOn
    updated.buryReviewSiblings = buryReviewSwitch.isOn
    updated.buryInterdayLearningSiblings = buryLearningSwitch.isOn
    if updated.fsrsEnabled {
      let historical = Double(historicalRetentionField.text ?? "")
      guard let value = historical, value >= 0.70, value <= 0.99 else {
        showAlert("历史记忆率必须在 0.70 到 0.99 之间。")
        return nil
      }
      updated.desiredRetention = Double(retentionSlider.value)
      updated.historicalRetention = value
    }
    return updated
  }

  private func commitVisibleLimits(to value: inout DeckOptions) -> Bool {
    commitLimitFields(scope: displayedLimitScope, to: &value, showError: true)
  }

  private func commitLimitFields(
    scope: LimitScope, to value: inout DeckOptions, showError: Bool
  ) -> Bool {
    let allowEmpty = scope != .preset
    guard let new = parseLimit(newLimitField, allowEmpty: allowEmpty),
      let reviews = parseLimit(reviewLimitField, allowEmpty: allowEmpty)
    else {
      if showError {
        showAlert(allowEmpty
          ? "每日限额必须是非负整数；留空表示继承。"
          : "预设每日限额必须是非负整数。")
      }
      return false
    }
    switch scope {
    case .preset:
      value.presetNewCardsPerDay = new!
      value.presetReviewsPerDay = reviews!
    case .deck:
      value.deckNewCardsPerDay = new
      value.deckReviewsPerDay = reviews
    case .today:
      value.todayNewCardsPerDay = new
      value.todayReviewsPerDay = reviews
    }
    return true
  }

  private func performSave(_ updated: DeckOptions) {
    activityIndicator.startAnimating()
    navigationItem.rightBarButtonItem?.isEnabled = false
    provider.saveOptions(updated) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.activityIndicator.stopAnimating()
        switch result {
        case .success:
          self.options = updated
          // Deck Options on Anki Desktop stays open after saving: users often
          // adjust a preset and its per-deck limits in the same session.
          self.apply(updated)
        case .failure(let error):
          self.navigationItem.rightBarButtonItem?.isEnabled = true
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  @objc private func selectInsertOrder() {
    presentChoices(title: "新卡插入顺序", button: insertOrderButton, choices: insertChoices)
  }
  @objc private func selectGatherOrder() {
    presentChoices(title: "新卡收集顺序", button: gatherOrderButton, choices: gatherChoices)
  }
  @objc private func selectSortOrder() {
    presentChoices(title: "新卡排序", button: sortOrderButton, choices: sortChoices)
  }
  @objc private func selectReviewOrder() {
    presentChoices(title: "复习排序", button: reviewOrderButton, choices: reviewChoices)
  }

  private func presentChoices(title: String, button: UIButton, choices: [(String, Int)]) {
    let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    for choice in choices {
      sheet.addAction(UIAlertAction(title: choice.0, style: .default) { [weak self] _ in
        self?.setChoice(button, value: choice.1, choices: choices)
        self?.markDirty(preset: true)
      })
    }
    sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
    sheet.popoverPresentationController?.sourceView = button
    sheet.popoverPresentationController?.sourceRect = button.bounds
    present(sheet, animated: true)
  }

  private func setChoice(_ button: UIButton, value: Int, choices: [(String, Int)]) {
    choiceValues[ObjectIdentifier(button)] = value
    button.setTitle(choices.first(where: { $0.1 == value })?.0 ?? "当前值 \(value)", for: .normal)
  }

  private var allTextFields: [UITextField] {
    [
      historicalRetentionField, newLimitField, reviewLimitField, learnStepsField,
      goodIntervalField, easyIntervalField, relearnStepsField, minimumLapseField,
      leechThresholdField, maximumReviewField,
    ]
  }

  private func isPresetField(_ field: UITextField) -> Bool {
    field === historicalRetentionField || field === learnStepsField
      || field === goodIntervalField || field === easyIntervalField
      || field === relearnStepsField || field === minimumLapseField
      || field === leechThresholdField || field === maximumReviewField
  }

  private func parseLimit(_ field: UITextField, allowEmpty: Bool) -> Int?? {
    let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return allowEmpty ? .some(nil) : nil }
    guard let value = Int(text), value >= 0 else { return nil }
    return .some(.some(value))
  }

  private func parseSteps(_ text: String?, allowEmpty: Bool) -> [Double]? {
    let parts = (text ?? "").split { $0 == " " || $0 == "," || $0 == ";" }
    if parts.isEmpty { return allowEmpty ? [] : nil }
    let values = parts.compactMap { Double($0) }
    guard values.count == parts.count, values.allSatisfy({ $0 > 0 && $0.isFinite }) else {
      showAlert("学习步骤应为用空格或逗号分隔的正数分钟。")
      return nil
    }
    return values
  }

  private func positiveInt(_ field: UITextField, name: String) -> Int? {
    guard let value = Int(field.text ?? ""), value > 0 else {
      showAlert("\(name)必须是正整数。")
      return nil
    }
    return value
  }

  private func nonnegativeInt(_ field: UITextField, name: String) -> Int? {
    guard let value = Int(field.text ?? ""), value >= 0 else {
      showAlert("\(name)必须是非负整数。")
      return nil
    }
    return value
  }

  private func formatSteps(_ values: [Double]) -> String {
    values.map(formatDecimal).joined(separator: " ")
  }

  private func formatDecimal(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.4g", value)
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
    label.numberOfLines = 0
    tertiaryLabels.append(label)
    return label
  }

  private func makeRowTitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DSTheme.bodyFont(size: 14)
    primaryLabels.append(label)
    return label
  }

  private func configureNumberField(_ field: UITextField, placeholder: String) {
    DSFormLayout.configureNumericField(field, placeholder: placeholder, keyboard: .numberPad)
  }

  private func configureDecimalField(_ field: UITextField, placeholder: String) {
    DSFormLayout.configureNumericField(field, placeholder: placeholder, keyboard: .decimalPad)
  }

  private func configureStepsField(_ field: UITextField, placeholder: String) {
    DSFormLayout.configureNumericField(
      field, placeholder: placeholder, keyboard: .numbersAndPunctuation)
  }

  private func configureChoiceButton(_ button: UIButton, action: Selector) {
    button.contentHorizontalAlignment = .right
    button.titleLabel?.font = DSTheme.bodyFont(size: 14)
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    button.addTarget(self, action: action, for: .touchUpInside)
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
  }

  private func addRows(_ rows: [(String, UIView)], to stack: UIStackView) {
    for (index, row) in rows.enumerated() {
      if index > 0 { stack.addArrangedSubview(separator()) }
      stack.addArrangedSubview(formRow(title: row.0, control: row.1))
    }
  }

  private func formRow(title: String, control: UIView) -> UIStackView {
    let row: UIStackView
    if let field = control as? UITextField {
      row = numericRow(title: title, field: field)
    } else if control is UISegmentedControl {
      row = labeledControlRow(title: title, control: control)
    } else {
      row = accessoryRow(title: title, control: control)
    }
    return row
  }

  private func numericRow(title: String, field: UITextField) -> UIStackView {
    let row = DSFormLayout.numericRow(title: title, field: field)
    trackPrimaryLabel(in: row)
    return row
  }

  private func labeledControlRow(title: String, control: UIView) -> UIStackView {
    let row = DSFormLayout.labeledControlRow(title: title, control: control)
    trackPrimaryLabel(in: row)
    return row
  }

  private func accessoryRow(title: String, control: UIView) -> UIStackView {
    let row = DSFormLayout.accessoryRow(title: title, control: control)
    trackPrimaryLabel(in: row)
    return row
  }

  private func trackPrimaryLabel(in row: UIStackView) {
    if let label = row.arrangedSubviews.first as? UILabel {
      primaryLabels.append(label)
    }
  }

  private func separator() -> UIView {
    let line = UIView()
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
