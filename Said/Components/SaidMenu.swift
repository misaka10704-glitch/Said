import UIKit

struct SaidMenuItem {
  let title: String
  let icon: ActionIconFactory.Kind?
  let isDestructive: Bool
  let isSelected: Bool
  let handler: () -> Void

  init(
    title: String,
    icon: ActionIconFactory.Kind? = nil,
    isDestructive: Bool = false,
    isSelected: Bool = false,
    handler: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.isDestructive = isDestructive
    self.isSelected = isSelected
    self.handler = handler
  }
}

/// Said's iOS 12-compatible floating action menu.
enum SaidMenu {
  static func present(
    from host: UIViewController,
    title: String? = nil,
    items: [SaidMenuItem],
    sourceView: UIView? = nil,
    sourceRect: CGRect? = nil,
    barButtonItem: UIBarButtonItem? = nil,
    preferAbove: Bool = false,
    preferVertical: Bool = false
  ) {
    guard !items.isEmpty else { return }

    var anchorRect: CGRect?
    if let item = barButtonItem,
      let itemView = item.value(forKey: "view") as? UIView
    {
      anchorRect = itemView.convert(itemView.bounds, to: nil)
    } else if let sourceView = sourceView {
      anchorRect = sourceView.convert(sourceRect ?? sourceView.bounds, to: nil)
    }

    let controller = SaidMenuViewController(titleText: title, items: items)
    controller.anchorWindowRect = anchorRect
    controller.preferAbove = preferAbove
    controller.preferVertical = preferVertical
    controller.modalPresentationStyle = .overFullScreen
    controller.modalTransitionStyle = .crossDissolve
    host.present(controller, animated: false)
  }
}

private final class SaidMenuViewController: UIViewController {
  private let titleText: String?
  private let items: [SaidMenuItem]
  private let backdrop = UIControl()
  private let card = UIView()
  private let clipView = UIView()
  private let scrollView = UIScrollView()
  private let stackView = UIStackView()
  private var rows: [SaidMenuRowView] = []
  private var separators: [UIView] = []
  private weak var titleLabel: UILabel?

  private var cardWidthConstraint: NSLayoutConstraint!
  private var cardHeightConstraint: NSLayoutConstraint!
  private var cardLeadingConstraint: NSLayoutConstraint!
  private var cardTopConstraint: NSLayoutConstraint!

  var anchorWindowRect: CGRect?
  var preferAbove = false
  var preferVertical = false

  init(titleText: String?, items: [SaidMenuItem]) {
    self.titleText = titleText
    self.items = items
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    backdrop.translatesAutoresizingMaskIntoConstraints = false
    backdrop.addTarget(self, action: #selector(dismissMenu), for: .touchUpInside)
    view.addSubview(backdrop)

    card.translatesAutoresizingMaskIntoConstraints = false
    card.layer.cornerRadius = 12
    view.addSubview(card)

    clipView.translatesAutoresizingMaskIntoConstraints = false
    clipView.layer.cornerRadius = 12
    clipView.clipsToBounds = true
    card.addSubview(clipView)

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsVerticalScrollIndicator = true
    scrollView.alwaysBounceVertical = false
    clipView.addSubview(scrollView)

    stackView.axis = .vertical
    stackView.alignment = .fill
    stackView.spacing = 0
    stackView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stackView)

    cardWidthConstraint = card.widthAnchor.constraint(equalToConstant: 252)
    cardHeightConstraint = card.heightAnchor.constraint(equalToConstant: 44)
    cardLeadingConstraint = card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20)
    cardTopConstraint = card.topAnchor.constraint(equalTo: view.topAnchor, constant: 80)

    NSLayoutConstraint.activate([
      backdrop.topAnchor.constraint(equalTo: view.topAnchor),
      backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      clipView.topAnchor.constraint(equalTo: card.topAnchor),
      clipView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
      clipView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      clipView.trailingAnchor.constraint(equalTo: card.trailingAnchor),

      scrollView.topAnchor.constraint(equalTo: clipView.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),

      stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 5),
      stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -5),
      stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

      cardWidthConstraint,
      cardHeightConstraint,
      cardLeadingConstraint,
      cardTopConstraint,
    ])

    buildRows()
    applyTheme()
    card.alpha = 0
    card.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
    backdrop.alpha = 0
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applyTheme),
      name: .saidThemeDidChange,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    positionCard()
    UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut], animations: {
      self.backdrop.alpha = 1
      self.card.alpha = 1
      self.card.transform = .identity
    })
  }

  override func viewWillTransition(
    to size: CGSize,
    with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: { _ in self.positionCard() })
  }

  private func buildRows() {
    if let rawTitle = titleText?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawTitle.isEmpty
    {
      let label = UILabel()
      label.text = rawTitle
      label.font = DSTheme.titleFont(size: 12)
      label.numberOfLines = 1
      label.lineBreakMode = .byTruncatingMiddle
      label.translatesAutoresizingMaskIntoConstraints = false
      let wrapper = UIView()
      wrapper.addSubview(label)
      NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
        label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6),
        label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
        label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
        wrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
      ])
      stackView.addArrangedSubview(wrapper)
      titleLabel = label
      stackView.addArrangedSubview(makeSeparator())
    }

    for (index, item) in items.enumerated() {
      if item.isDestructive, index > 0, !items[index - 1].isDestructive {
        stackView.addArrangedSubview(makeSeparator())
      }
      let row = SaidMenuRowView(item: item, index: index)
      row.onTap = { [weak self] selectedIndex in
        self?.selectItem(at: selectedIndex)
      }
      rows.append(row)
      stackView.addArrangedSubview(row)
    }
  }

  private func makeSeparator() -> UIView {
    let wrapper = UIView()
    let line = UIView()
    line.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(line)
    NSLayoutConstraint.activate([
      wrapper.heightAnchor.constraint(equalToConstant: 11),
      line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
      line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
      line.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
      line.heightAnchor.constraint(equalToConstant: DSTheme.List.separatorHeight),
    ])
    separators.append(line)
    return wrapper
  }

  @objc private func applyTheme() {
    let colors = DSTheme.c
    let isDark = ThemeManager.shared.mode == .dark
    backdrop.backgroundColor = UIColor.black.withAlphaComponent(isDark ? 0.24 : 0.10)
    card.backgroundColor = colors.surface
    clipView.backgroundColor = colors.surface
    card.layer.borderWidth = DSTheme.List.separatorHeight
    card.layer.borderColor = colors.border.cgColor
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = isDark ? 0.45 : 0.14
    card.layer.shadowRadius = isDark ? 20 : 14
    card.layer.shadowOffset = CGSize(width: 0, height: 8)
    titleLabel?.textColor = colors.textTertiary
    separators.forEach { $0.backgroundColor = colors.divider }
    rows.forEach { $0.applyTheme() }
  }

  private func positionCard() {
    let margin: CGFloat = 14
    let width = min(CGFloat(280), max(CGFloat(220), view.bounds.width - margin * 2))
    cardWidthConstraint.constant = width
    view.layoutIfNeeded()

    let contentHeight = stackView.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height + 10
    let safeFrame = view.safeAreaLayoutGuide.layoutFrame
    let maxHeight = max(44, safeFrame.height - margin * 2)
    let height = min(maxHeight, max(44, contentHeight))
    cardHeightConstraint.constant = height
    scrollView.isScrollEnabled = contentHeight > height

    var x = (view.bounds.width - width) / 2
    var y = safeFrame.minY + safeFrame.height * 0.24
    if let windowRect = anchorWindowRect {
      let rect = view.convert(windowRect, from: nil)
      let roomAbove = rect.minY - safeFrame.minY - margin
      let roomBelow = safeFrame.maxY - rect.maxY - margin
      let forceVertical = preferVertical || preferAbove || rect.width > 96
      let shouldPlaceAbove =
        preferAbove || rect.midY > safeFrame.midY || roomBelow < height + 8

      if !forceVertical, view.bounds.width - rect.maxX - margin >= width + 8, !shouldPlaceAbove {
        x = rect.maxX + 8
        y = rect.midY - 22
      } else {
        x = rect.minX
        if shouldPlaceAbove, roomAbove >= height + 8 {
          y = rect.minY - height - 8
        } else if roomBelow >= height + 8 {
          y = rect.maxY + 8
        } else {
          y = safeFrame.minY + margin
        }
      }
    }

    x = min(max(margin, x), view.bounds.width - width - margin)
    y = min(max(safeFrame.minY + margin, y), safeFrame.maxY - height - margin)
    cardLeadingConstraint.constant = x
    cardTopConstraint.constant = y
    view.layoutIfNeeded()
  }

  private func selectItem(at index: Int) {
    guard items.indices.contains(index) else { return }
    let handler = items[index].handler
    hideMenu {
      self.dismiss(animated: false, completion: handler)
    }
  }

  @objc private func dismissMenu() {
    hideMenu {
      self.dismiss(animated: false)
    }
  }

  private func hideMenu(completion: @escaping () -> Void) {
    UIView.animate(
      withDuration: 0.12,
      animations: {
        self.backdrop.alpha = 0
        self.card.alpha = 0
        self.card.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
      },
      completion: { _ in completion() }
    )
  }
}

private final class SaidMenuRowView: UIView {
  var onTap: ((Int) -> Void)?

  private let item: SaidMenuItem
  private let index: Int
  private let highlightView = UIView()
  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private let checkLabel = UILabel()
  private let button = UIButton(type: .custom)

  init(item: SaidMenuItem, index: Int) {
    self.item = item
    self.index = index
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false
    highlightView.translatesAutoresizingMaskIntoConstraints = false
    highlightView.layer.cornerRadius = 8
    highlightView.alpha = 0
    addSubview(highlightView)

    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentMode = .scaleAspectFit
    iconView.image = item.icon.map { ActionIconFactory.image($0, pointSize: 16) }
    iconView.isHidden = item.icon == nil
    addSubview(iconView)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = item.title
    titleLabel.font = DSTheme.bodyFont(size: 15)
    titleLabel.lineBreakMode = .byTruncatingTail
    addSubview(titleLabel)

    checkLabel.translatesAutoresizingMaskIntoConstraints = false
    checkLabel.text = item.isSelected ? "✓" : nil
    checkLabel.font = DSTheme.titleFont(size: 14)
    checkLabel.textAlignment = .center
    checkLabel.accessibilityLabel = item.isSelected ? "已选择" : nil
    addSubview(checkLabel)

    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = item.title
    button.addTarget(self, action: #selector(touchDown), for: .touchDown)
    button.addTarget(
      self,
      action: #selector(touchUp),
      for: [.touchUpInside, .touchUpOutside, .touchCancel]
    )
    button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
    addSubview(button)

    let iconWidth: CGFloat = item.icon == nil ? 0 : 18
    let titleSpacing: CGFloat = item.icon == nil ? 14 : 10
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 42),
      highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
      highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: iconWidth),
      iconView.heightAnchor.constraint(equalToConstant: 18),
      titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: titleSpacing),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkLabel.leadingAnchor, constant: -8),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      checkLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      checkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      checkLabel.widthAnchor.constraint(equalToConstant: item.isSelected ? 18 : 0),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor),
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    let colors = DSTheme.c
    titleLabel.textColor = item.isDestructive ? colors.destructive : colors.textPrimary
    iconView.tintColor = item.isDestructive ? colors.destructive : colors.textSecondary
    checkLabel.textColor = colors.accent
    highlightView.backgroundColor = colors.surfaceHover
  }

  @objc private func touchDown() {
    highlightView.alpha = 1
  }

  @objc private func touchUp() {
    highlightView.alpha = 0
  }

  @objc private func tapped() {
    onTap?(index)
  }
}
