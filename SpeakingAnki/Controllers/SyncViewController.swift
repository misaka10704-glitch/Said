import UIKit

final class SyncViewController: UIViewController, ThemeRefreshable {
  private let provider: SyncDataProviding
  private let scrollView = UIScrollView()
  private let contentStack = UIStackView()
  private let stateLabel = UILabel()

  private let loginStack = UIStackView()
  private let usernameField = UITextField()
  private let passwordField = UITextField()
  private let loginButton = DSButton(style: .primary)

  private let accountStack = UIStackView()
  private let accountLabel = UILabel()
  private let syncButton = DSButton(style: .primary)
  private let logoutButton = DSButton(style: .secondary)

  private let progressStack = UIStackView()
  private let progressView = UIProgressView(progressViewStyle: .default)
  private let progressLabel = UILabel()
  private let cancelButton = DSButton(style: .secondary)

  private let conflictStack = UIStackView()
  private let localConflictLabel = UILabel()
  private let remoteConflictLabel = UILabel()
  private let uploadButton = DSButton(style: .primary)
  private let downloadButton = DSButton(style: .secondary)
  private var formSections: [DSFormSection] = []
  private var titleLabels: [UILabel] = []
  private var subtitleLabels: [UILabel] = []

  init(provider: SyncDataProviding) {
    self.provider = provider
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "同步"
    configureViews()
    applyTheme()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
    provider.stateDidChange = { [weak self] phase in
      DispatchQueue.main.async { self?.render(phase) }
    }
    provider.currentState { [weak self] phase in
      DispatchQueue.main.async { self?.render(phase) }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureViews() {
    scrollView.alwaysBounceVertical = true
    scrollView.keyboardDismissMode = .interactive
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.spacing = 18
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    stateLabel.font = DSTheme.bodyFont(size: 14)
    stateLabel.textAlignment = .center
    stateLabel.numberOfLines = 0
    contentStack.addArrangedSubview(stateLabel)

    configureLoginStack()
    configureAccountStack()
    configureProgressStack()
    configureConflictStack()

    view.addSubview(scrollView)
    scrollView.addSubview(contentStack)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 32),
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

  private func configureLoginStack() {
    styleContentStack(loginStack)
    let section = formSection("AnkiWeb 账户")
    let title = cardTitle("登录 AnkiWeb")
    let subtitle = cardSubtitle("登录后可在设备之间同步当前集合。")
    configureTextField(usernameField, placeholder: "邮箱或用户名", secure: false)
    usernameField.keyboardType = .emailAddress
    usernameField.textContentType = .username
    configureTextField(passwordField, placeholder: "密码", secure: true)
    passwordField.textContentType = .password
    configurePrimaryButton(loginButton, title: "登录", selector: #selector(logIn))
    loginStack.addArrangedSubview(title)
    loginStack.addArrangedSubview(subtitle)
    loginStack.addArrangedSubview(usernameField)
    loginStack.addArrangedSubview(passwordField)
    loginStack.addArrangedSubview(loginButton)
    section.addRow(loginStack, separated: false)
    contentStack.addArrangedSubview(section)
  }

  private func configureAccountStack() {
    styleContentStack(accountStack)
    accountLabel.font = DSTheme.titleFont(size: 18)
    accountLabel.textColor = DSTheme.c.textPrimary
    accountLabel.textAlignment = .center
    configurePrimaryButton(syncButton, title: "立即同步", selector: #selector(startSync))
    configureSecondaryButton(logoutButton, title: "退出登录", selector: #selector(logOut))
    accountStack.addArrangedSubview(cardTitle("同步已就绪"))
    accountStack.addArrangedSubview(accountLabel)
    accountStack.addArrangedSubview(syncButton)
    accountStack.addArrangedSubview(logoutButton)
    let section = formSection("同步状态")
    section.addRow(accountStack, separated: false)
    contentStack.addArrangedSubview(section)
  }

  private func configureProgressStack() {
    styleContentStack(progressStack)
    progressLabel.font = DSTheme.bodyFont(size: 14)
    progressLabel.textColor = DSTheme.c.textSecondary
    progressLabel.numberOfLines = 0
    progressLabel.textAlignment = .center
    progressView.progressTintColor = DSTheme.c.accent
    progressView.trackTintColor = DSTheme.c.surfaceHover
    configureSecondaryButton(cancelButton, title: "取消同步", selector: #selector(cancelSync))
    progressStack.addArrangedSubview(cardTitle("正在同步"))
    progressStack.addArrangedSubview(progressView)
    progressStack.addArrangedSubview(progressLabel)
    progressStack.addArrangedSubview(cancelButton)
    let section = formSection("同步进度")
    section.addRow(progressStack, separated: false)
    contentStack.addArrangedSubview(section)
  }

  private func configureConflictStack() {
    styleContentStack(conflictStack)
    conflictStack.addArrangedSubview(cardTitle("需要完整同步"))
    conflictStack.addArrangedSubview(
      cardSubtitle(
        "本机与远端集合无法合并，请选择要保留的副本。"
      ))
    configureConflictLabel(localConflictLabel)
    configureConflictLabel(remoteConflictLabel)
    configurePrimaryButton(uploadButton, title: "上传本机集合", selector: #selector(uploadLocal))
    configureSecondaryButton(
      downloadButton,
      title: "从 AnkiWeb 下载",
      selector: #selector(downloadRemote)
    )
    conflictStack.addArrangedSubview(localConflictLabel)
    conflictStack.addArrangedSubview(uploadButton)
    conflictStack.addArrangedSubview(remoteConflictLabel)
    conflictStack.addArrangedSubview(downloadButton)
    let section = formSection("同步冲突")
    section.addRow(conflictStack, separated: false)
    contentStack.addArrangedSubview(section)
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    scrollView.backgroundColor = colors.background
    stateLabel.textColor = colors.textSecondary
    accountLabel.textColor = colors.textPrimary
    progressLabel.textColor = colors.textSecondary
    for label in [localConflictLabel, remoteConflictLabel] {
      label.textColor = colors.textSecondary
    }
    for label in titleLabels { label.textColor = colors.textPrimary }
    for label in subtitleLabels { label.textColor = colors.textSecondary }
    for section in formSections { section.applyTheme() }
    for field in [usernameField, passwordField] {
      field.textColor = colors.textPrimary
      field.backgroundColor = colors.inputBackground
      field.layer.borderColor = colors.inputBorder.cgColor
      field.keyboardAppearance = ThemeManager.shared.mode == .dark ? .dark : .light
    }
    progressView.progressTintColor = colors.accent
    progressView.trackTintColor = colors.surfaceHover
    for button in [
      loginButton, syncButton, logoutButton, cancelButton, uploadButton, downloadButton,
    ] {
      button.applyTheme()
    }
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  private func render(_ phase: SyncPhase) {
    for section in formSections { section.isHidden = true }
    loginButton.isEnabled = true

    switch phase {
    case .signedOut:
      stateLabel.text = nil
      formSections[0].isHidden = false
    case .authenticating:
      stateLabel.text = "正在登录…"
      formSections[0].isHidden = false
      loginButton.isEnabled = false
    case .ready(let accountName):
      stateLabel.text = "集合已准备好，可以同步。"
      accountLabel.text = accountName
      formSections[1].isHidden = false
    case .syncing(let progress, let message):
      stateLabel.text = nil
      progressView.progress = min(max(progress, 0), 1)
      progressLabel.text = message
      formSections[2].isHidden = false
    case .conflict(let localDescription, let remoteDescription):
      stateLabel.text = nil
      localConflictLabel.text = "本机\n\(localDescription)"
      remoteConflictLabel.text = "ANKIWEB\n\(remoteDescription)"
      formSections[3].isHidden = false
    case .completed(let message):
      stateLabel.text = message
      accountLabel.text = "已连接"
      formSections[1].isHidden = false
    case .failed(let message):
      stateLabel.text = message
      formSections[0].isHidden = false
    }
  }

  @objc private func logIn() {
    let username = (usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let password = passwordField.text ?? ""
    guard !username.isEmpty, !password.isEmpty else {
      stateLabel.text = "请输入账户名和密码。"
      return
    }
    view.endEditing(true)
    provider.logIn(credentials: SyncCredentials(username: username, password: password))
  }

  @objc private func logOut() {
    passwordField.text = nil
    provider.logOut()
  }

  @objc private func startSync() {
    provider.startSync()
  }

  @objc private func cancelSync() {
    provider.cancelSync()
  }

  @objc private func uploadLocal() {
    confirmResolution(
      title: "替换 AnkiWeb 集合？",
      message: "本机集合将覆盖 AnkiWeb 上的副本。",
      resolution: .uploadLocal
    )
  }

  @objc private func downloadRemote() {
    confirmResolution(
      title: "替换本机集合？",
      message: "本机集合将被 AnkiWeb 上的副本替换。",
      resolution: .downloadRemote
    )
  }

  private func confirmResolution(
    title: String,
    message: String,
    resolution: SyncConflictResolution
  ) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
        self?.provider.resolveConflict(resolution)
      })
    present(alert, animated: true)
  }

  private func formSection(_ title: String) -> DSFormSection {
    let section = DSFormSection(title: title)
    formSections.append(section)
    return section
  }

  private func styleContentStack(_ stack: UIStackView) {
    stack.axis = .vertical
    stack.spacing = 14
  }

  private func cardTitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DSTheme.titleFont(size: 19)
    label.textColor = DSTheme.c.textPrimary
    label.textAlignment = .center
    label.numberOfLines = 0
    titleLabels.append(label)
    return label
  }

  private func cardSubtitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DSTheme.bodyFont(size: 14)
    label.textColor = DSTheme.c.textSecondary
    label.textAlignment = .center
    label.numberOfLines = 0
    subtitleLabels.append(label)
    return label
  }

  private func configureTextField(_ field: UITextField, placeholder: String, secure: Bool) {
    field.placeholder = placeholder
    field.isSecureTextEntry = secure
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.font = DSTheme.bodyFont(size: 16)
    field.textColor = DSTheme.c.textPrimary
    field.backgroundColor = DSTheme.c.inputBackground
    field.layer.borderColor = DSTheme.c.inputBorder.cgColor
    field.layer.borderWidth = 1
    field.layer.cornerRadius = 9
    field.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let spacer = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
    field.leftView = spacer
    field.leftViewMode = .always
  }

  private func configurePrimaryButton(_ button: DSButton, title: String, selector: Selector) {
    configureButton(button, title: title, selector: selector)
  }

  private func configureSecondaryButton(_ button: DSButton, title: String, selector: Selector) {
    configureButton(button, title: title, selector: selector)
  }

  private func configureButton(_ button: DSButton, title: String, selector: Selector) {
    button.setTitle(title, for: .normal)
    button.addTarget(self, action: selector, for: .touchUpInside)
  }

  private func configureConflictLabel(_ label: UILabel) {
    label.font = DSTheme.bodyFont(size: 13)
    label.textColor = DSTheme.c.textSecondary
    label.numberOfLines = 0
    label.textAlignment = .center
  }
}
