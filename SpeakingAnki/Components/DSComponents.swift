import UIKit

extension NSLayoutConstraint {
  func withPriority(_ value: Float) -> NSLayoutConstraint {
    priority = UILayoutPriority(value)
    return self
  }
}

enum DSNavigationBarStyle {
  static func apply(to navigationController: UINavigationController) {
    let colors = DSTheme.c
    let bar = navigationController.navigationBar
    bar.isTranslucent = false
    bar.barStyle = colors.navBarStyle
    bar.barTintColor = colors.surface
    bar.tintColor = colors.accent
    bar.titleTextAttributes = [.foregroundColor: colors.textPrimary]
    bar.setBackgroundImage(pixelImage(color: colors.surface), for: .default)
    bar.shadowImage = pixelImage(color: colors.divider)
    navigationController.view.backgroundColor = colors.background
  }

  private static func pixelImage(color: UIColor) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 1, height: 1), false, 0)
    defer { UIGraphicsEndImageContext() }
    color.setFill()
    UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
    return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
  }
}

final class DSButton: UIButton, ThemeRefreshable {
  enum Style {
    case primary
    case secondary
  }

  let style: Style

  init(style: Style) {
    self.style = style
    super.init(frame: .zero)
    titleLabel?.font = DSTheme.titleFont(size: 15)
    layer.cornerRadius = DSTheme.Form.cornerRadius
    heightAnchor.constraint(equalToConstant: DSTheme.Form.controlHeight).isActive = true
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isEnabled: Bool {
    didSet { alpha = isEnabled ? 1 : 0.48 }
  }

  func applyTheme() {
    let colors = DSTheme.c
    switch style {
    case .primary:
      backgroundColor = colors.accent
      setTitleColor(.white, for: .normal)
    case .secondary:
      backgroundColor = colors.surfaceHover
      setTitleColor(colors.textPrimary, for: .normal)
    }
  }
}

/// A small, reusable surface for grouped list rows or form controls.
final class DSContainerView: UIView, ThemeRefreshable {
  enum Kind {
    case form
    case list
  }

  let stackView = UIStackView()
  private let kind: Kind

  init(kind: Kind) {
    self.kind = kind
    super.init(frame: .zero)
    stackView.axis = .vertical
    stackView.spacing = kind == .form ? DSTheme.Form.rowSpacing : 0
    stackView.isLayoutMarginsRelativeArrangement = true
    stackView.layoutMargins =
      kind == .form
      ? DSTheme.Form.cardInsets
      : UIEdgeInsets(
        top: 0, left: DSTheme.List.horizontalInset, bottom: 0, right: DSTheme.List.horizontalInset)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stackView)
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: topAnchor),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    layer.borderWidth = DSTheme.List.separatorHeight
    layer.cornerRadius = DSTheme.cornerRadius
    layer.masksToBounds = true
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    backgroundColor = DSTheme.c.surface
    layer.borderColor = DSTheme.c.border.cgColor
  }
}

final class DSEmptyStateView: UIView, ThemeRefreshable {
  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private let detailLabel = UILabel()

  init(icon: ActionIconFactory.Kind, title: String, detail: String? = nil) {
    super.init(frame: .zero)
    iconView.image = ActionIconFactory.image(icon, pointSize: 28)
    iconView.contentMode = .center
    titleLabel.text = title
    titleLabel.font = DSTheme.titleFont(size: 17)
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 0
    detailLabel.text = detail
    detailLabel.font = DSTheme.bodyFont(size: 14)
    detailLabel.textAlignment = .center
    detailLabel.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, detailLabel])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = DSTheme.Spacing.xs
    stack.setCustomSpacing(DSTheme.Spacing.md, after: iconView)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: leadingAnchor, constant: DSTheme.Spacing.lg),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor, constant: -DSTheme.Spacing.lg),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
      iconView.heightAnchor.constraint(equalToConstant: 40),
    ])
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    backgroundColor = .clear
    iconView.tintColor = DSTheme.c.textTertiary
    titleLabel.textColor = DSTheme.c.textPrimary
    detailLabel.textColor = DSTheme.c.textSecondary
  }
}

final class DSSectionLabel: UILabel, ThemeRefreshable {
  init(_ text: String) {
    super.init(frame: .zero)
    self.text = text
    font = DSTheme.titleFont(size: 12)
    numberOfLines = 0
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    textColor = DSTheme.c.textSecondary
  }
}

/// An Anki-style grouped form section backed by the shared design-system surface.
final class DSFormSection: UIStackView, ThemeRefreshable {
  let content = DSContainerView(kind: .form)

  init(title: String, detail: String? = nil) {
    super.init(frame: .zero)
    axis = .vertical
    spacing = DSTheme.Spacing.xs
    addArrangedSubview(DSSectionLabel(title))
    addArrangedSubview(content)
    if let detail = detail {
      let label = UILabel()
      label.text = detail
      label.font = DSTheme.bodyFont(size: 12)
      label.numberOfLines = 0
      label.tag = 9001
      addArrangedSubview(label)
    }
    applyTheme()
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func addRow(_ view: UIView, separated: Bool = true) {
    if separated, !content.stackView.arrangedSubviews.isEmpty {
      let divider = UIView()
      divider.tag = 9002
      divider.heightAnchor.constraint(equalToConstant: DSTheme.List.separatorHeight).isActive = true
      content.stackView.addArrangedSubview(divider)
    }
    content.stackView.addArrangedSubview(view)
  }

  func applyTheme() {
    content.applyTheme()
    for refreshable in arrangedSubviews.compactMap({ $0 as? ThemeRefreshable }) {
      refreshable.applyTheme()
    }
    (viewWithTag(9001) as? UILabel)?.textColor = DSTheme.c.textTertiary
    for divider in content.stackView.arrangedSubviews where divider.tag == 9002 {
      divider.backgroundColor = DSTheme.c.divider
    }
    for subview in content.subviews {
      refreshTheme(in: subview)
    }
  }

  private func refreshTheme(in view: UIView) {
    (view as? ThemeRefreshable)?.applyTheme()
    for subview in view.subviews {
      refreshTheme(in: subview)
    }
  }
}

final class DSFormRow: UIStackView, ThemeRefreshable {
  private let titleLabel = UILabel()
  private let detailLabel = UILabel()

  init(title: String, detail: String? = nil, control: UIView? = nil) {
    super.init(frame: .zero)
    axis = .horizontal
    alignment = .center
    spacing = DSTheme.Form.rowSpacing

    titleLabel.text = title
    titleLabel.font = DSTheme.bodyFont(size: 15)
    titleLabel.numberOfLines = 0
    detailLabel.text = detail
    detailLabel.font = DSTheme.bodyFont(size: 12)
    detailLabel.numberOfLines = 0

    let labels = UIStackView(
      arrangedSubviews: detail == nil ? [titleLabel] : [titleLabel, detailLabel])
    labels.axis = .vertical
    labels.spacing = 3
    addArrangedSubview(labels)
    if let control = control {
      addArrangedSubview(control)
    }
    heightAnchor.constraint(greaterThanOrEqualToConstant: DSTheme.Form.compactControlHeight)
      .isActive = true
    applyTheme()
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    titleLabel.textColor = DSTheme.c.textPrimary
    detailLabel.textColor = DSTheme.c.textTertiary
  }
}

final class DSTextField: UITextField, ThemeRefreshable {
  init(placeholder: String, secure: Bool = false) {
    super.init(frame: .zero)
    self.placeholder = placeholder
    isSecureTextEntry = secure
    autocapitalizationType = .none
    autocorrectionType = .no
    font = DSTheme.bodyFont(size: 15)
    layer.borderWidth = DSTheme.List.separatorHeight
    layer.cornerRadius = DSTheme.Form.cornerRadius
    heightAnchor.constraint(equalToConstant: DSTheme.Form.controlHeight).isActive = true
    let inset = UIView(
      frame: CGRect(x: 0, y: 0, width: DSTheme.Form.fieldHorizontalInset, height: 1))
    leftView = inset
    leftViewMode = .always
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    backgroundColor = DSTheme.c.inputBackground
    textColor = DSTheme.c.textPrimary
    tintColor = DSTheme.c.accent
    layer.borderColor = DSTheme.c.inputBorder.cgColor
    keyboardAppearance = ThemeManager.shared.mode == .dark ? .dark : .light
  }
}
