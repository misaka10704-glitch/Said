import UIKit

final class SettingsViewController: UIViewController, ThemeRefreshable {
  private let scroll = UIScrollView()
  private let stack = UIStackView()

  private let azureKeyField = DSTextField(placeholder: "Azure Speech 密钥", secure: true)
  private let azureRegionField = DSTextField(placeholder: "Azure 区域（如 eastasia）")
  private let dashKeyField = DSTextField(placeholder: "DashScope API 密钥", secure: true)
  private let dashBaseField = DSTextField(placeholder: "DashScope Base URL")
  private let appearanceControl = UISegmentedControl(items: ["浅色", "深色"])
  private let interfaceScaleControl = UISlider()
  private let dataMaintenanceButton = DSButton(style: .secondary)
  private let edgeTTSBatchButton = DSButton(style: .secondary)
  private let translationBatchButton = DSButton(style: .secondary)

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "设置"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "保存", style: .done, target: self, action: #selector(save))

    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.keyboardDismissMode = .interactive
    scroll.alwaysBounceVertical = true
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    scroll.addSubview(stack)

    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuideTop),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: scroll.contentLayoutGuide.leadingAnchor,
        constant: DSTheme.contentPadding),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: scroll.contentLayoutGuide.trailingAnchor,
        constant: -DSTheme.contentPadding),
      stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      stack.widthAnchor.constraint(
        equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -DSTheme.contentPadding * 2
      ).withPriority(750),
    ])

    let appearanceSection = DSFormSection(title: "外观")
    appearanceControl.selectedSegmentIndex =
      AppearanceMode.allCases.firstIndex(of: ThemeManager.shared.mode) ?? 1
    appearanceControl.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
    appearanceControl.heightAnchor.constraint(equalToConstant: 34).isActive = true
    appearanceSection.addRow(
      DSFormLayout.labeledControlRow(title: "主题", control: appearanceControl),
      separated: true
    )
    interfaceScaleControl.minimumValue = 0.85
    interfaceScaleControl.maximumValue = 1.3
    interfaceScaleControl.value = Float(ThemeManager.shared.interfaceScale)
    interfaceScaleControl.addTarget(self, action: #selector(interfaceScaleChanged), for: .valueChanged)
    appearanceSection.addRow(
      DSFormLayout.labeledControlRow(title: "界面大小", control: interfaceScaleControl),
      separated: false
    )
    stack.addArrangedSubview(appearanceSection)

    let dataSection = DSFormSection(
      title: "数据",
      detail: "备份、恢复、数据库检查，以及 APKG、COLPKG 和 CSV 的导入导出。"
    )
    dataMaintenanceButton.setTitle("本地数据维护中心", for: .normal)
    dataMaintenanceButton.addTarget(
      self,
      action: #selector(openDataMaintenance),
      for: .touchUpInside
    )
    dataSection.addRow(dataMaintenanceButton, separated: false)
    stack.addArrangedSubview(dataSection)

    let ttsSection = DSFormSection(
      title: "Edge TTS 参考音",
      detail: "按牌组批量预生成参考音。已有本地缓存会自动跳过，复习时无需等待生成。"
    )
    edgeTTSBatchButton.setTitle("批量生成参考音", for: .normal)
    edgeTTSBatchButton.addTarget(self, action: #selector(openEdgeTTSBatch), for: .touchUpInside)
    ttsSection.addRow(edgeTTSBatchButton, separated: false)
    stack.addArrangedSubview(ttsSection)

    let translationSection = DSFormSection(
      title: "中文翻译",
      detail: "按牌组批量翻译本 App 新增的卡片。已有中文的正常显示；仅带 trans 标签的笔记会进入翻译队列。"
    )
    translationBatchButton.setTitle("批量翻译中文", for: .normal)
    translationBatchButton.addTarget(
      self, action: #selector(openTranslationBatch), for: .touchUpInside)
    translationSection.addRow(translationBatchButton, separated: false)
    stack.addArrangedSubview(translationSection)

    let azureSection = DSFormSection(title: "Azure Speech")
    azureSection.addRow(azureKeyField, separated: false)
    azureSection.addRow(azureRegionField)
    stack.addArrangedSubview(azureSection)

    let dashSection = DSFormSection(title: "Qwen / DashScope（口语表达与翻译）")
    dashSection.addRow(dashKeyField, separated: false)
    dashSection.addRow(dashBaseField)
    stack.addArrangedSubview(dashSection)

    let note = UILabel()
    note.numberOfLines = 0
    note.font = DSTheme.bodyFont(size: 13)
    note.tag = 101
    note.text = """
      密钥仅存本机 Keychain，不写进源码。
      Mode A：Pronounce_Learning / 轻听 → 录音 + Azure 发音评分。
      Mode B：Speaking Compose → 录音 + Azure + Qwen Fix/Better。
      进度通过「导出 .apkg」带回桌面 Anki（先备份桌面库）。
      目标系统：iOS 12 / iPad Air 1。
      """
    let noteSection = DSFormSection(title: "说明")
    noteSection.addRow(note, separated: false)
    stack.addArrangedSubview(noteSection)

    azureKeyField.text = KeychainStore.get(.azureSpeechKey)
    azureRegionField.text = KeychainStore.get(.azureSpeechRegion)
    dashKeyField.text = KeychainStore.get(.dashscopeKey)
    dashBaseField.text = KeychainStore.get(.dashscopeBase)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillHide(_:)),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )
    applyTheme()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private var safeAreaLayoutGuideTop: NSLayoutYAxisAnchor {
    if #available(iOS 11.0, *) {
      return view.safeAreaLayoutGuide.topAnchor
    }
    return topLayoutGuide.bottomAnchor
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    scroll.backgroundColor = colors.background
    appearanceControl.tintColor = colors.accent
    appearanceControl.setTitleTextAttributes([.foregroundColor: colors.textSecondary], for: .normal)
    appearanceControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    dataMaintenanceButton.setTitleColor(colors.accent, for: .normal)
    edgeTTSBatchButton.setTitleColor(colors.accent, for: .normal)
    translationBatchButton.setTitleColor(colors.accent, for: .normal)

    for field in [azureKeyField, azureRegionField, dashKeyField, dashBaseField] {
      field.applyTheme()
    }
    dataMaintenanceButton.applyTheme()
    edgeTTSBatchButton.applyTheme()
    translationBatchButton.applyTheme()
    refreshTheme(in: stack)

    for label in stack.arrangedSubviews.compactMap({ $0 as? UILabel }) {
      label.textColor = label.tag == 101 ? colors.textSecondary : colors.textPrimary
    }
  }

  private func refreshTheme(in view: UIView) {
    for subview in view.subviews {
      (subview as? ThemeRefreshable)?.applyTheme()
      refreshTheme(in: subview)
    }
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  @objc private func keyboardWillChangeFrame(_ notification: Notification) {
    guard
      let info = notification.userInfo,
      let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    else { return }
    let keyboardFrame = view.convert(frame, from: nil)
    let overlap = max(0, view.bounds.maxY - keyboardFrame.minY)
    updateKeyboardInset(overlap, notification: notification)
    guard let responder = firstResponder(in: view) else { return }
    let target = responder.convert(responder.bounds, to: scroll).insetBy(dx: 0, dy: -20)
    scroll.scrollRectToVisible(target, animated: true)
  }

  @objc private func keyboardWillHide(_ notification: Notification) {
    updateKeyboardInset(0, notification: notification)
  }

  private func updateKeyboardInset(_ bottom: CGFloat, notification: Notification) {
    let info = notification.userInfo ?? [:]
    let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue
      ?? 0.25
    let rawCurve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
      ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
    let options = UIView.AnimationOptions(rawValue: rawCurve << 16)
    UIView.animate(withDuration: duration, delay: 0, options: options) {
      self.scroll.contentInset.bottom = bottom
      self.scroll.scrollIndicatorInsets.bottom = bottom
      self.view.layoutIfNeeded()
    }
  }

  private func firstResponder(in root: UIView) -> UIView? {
    if root.isFirstResponder { return root }
    for child in root.subviews {
      if let responder = firstResponder(in: child) { return responder }
    }
    return nil
  }

  @objc private func appearanceChanged() {
    let modes = AppearanceMode.allCases
    guard modes.indices.contains(appearanceControl.selectedSegmentIndex) else { return }
    ThemeManager.shared.mode = modes[appearanceControl.selectedSegmentIndex]
  }

  @objc private func interfaceScaleChanged() {
    ThemeManager.shared.interfaceScale = CGFloat(interfaceScaleControl.value)
  }

  @objc private func openDataMaintenance() {
    navigationController?.pushViewController(DataMaintenanceViewController(), animated: true)
  }

  @objc private func openEdgeTTSBatch() {
    navigationController?.pushViewController(EdgeTTSBatchViewController(), animated: true)
  }

  @objc private func openTranslationBatch() {
    navigationController?.pushViewController(TranslationBatchViewController(), animated: true)
  }

  @objc private func save() {
    KeychainStore.set(azureKeyField.text ?? "", for: .azureSpeechKey)
    KeychainStore.set(
      (azureRegionField.text ?? "").isEmpty ? "eastasia" : (azureRegionField.text ?? ""),
      for: .azureSpeechRegion)
    KeychainStore.set(dashKeyField.text ?? "", for: .dashscopeKey)
    let base = dashBaseField.text ?? ""
    KeychainStore.set(
      base.isEmpty ? "https://dashscope.aliyuncs.com/compatible-mode/v1" : base, for: .dashscopeBase
    )
    let a = UIAlertController(title: nil, message: "已保存", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "好", style: .default))
    present(a, animated: true)
  }
}
