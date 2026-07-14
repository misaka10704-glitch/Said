import UIKit

enum SaidSection: Int, CaseIterable {
    case decks
    case browse
    case stats
    case sync
    case settings

    var title: String {
        switch self {
        case .decks: return "牌组"
        case .browse: return "浏览"
        case .stats: return "统计"
        case .sync: return "同步"
        case .settings: return "设置"
        }
    }

    var icon: ActionIconFactory.Kind {
        switch self {
        case .decks: return .decks
        case .browse: return .browse
        case .stats: return .stats
        case .sync: return .sync
        case .settings: return .settings
        }
    }
}

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelect section: SaidSection)
}

final class SidebarViewController: UIViewController, ThemeRefreshable, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?

    private let headerView = UIView()
    private let logoView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let divider = UIView()
    private var selectedSection: SaidSection = .decks

    override func viewDidLoad() {
        super.viewDidLoad()
        buildView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .saidThemeDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func select(_ section: SaidSection) {
        selectedSection = section
        tableView.reloadData()
    }

    func applyTheme() {
        let colors = DSTheme.c
        view.backgroundColor = colors.sidebarBackground
        headerView.backgroundColor = colors.sidebarBackground
        tableView.backgroundColor = colors.sidebarBackground
        titleLabel.textColor = colors.textPrimary
        subtitleLabel.textColor = colors.textTertiary
        divider.backgroundColor = colors.divider
        tableView.reloadData()
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func buildView() {
        preferredContentSize = CGSize(width: DSTheme.sidebarWidth, height: 0)

        [headerView, divider, tableView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.image = UIImage(named: "SaidLogo")
        logoView.contentMode = .scaleAspectFit
        logoView.clipsToBounds = true
        logoView.layer.cornerRadius = 8
        headerView.addSubview(logoView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Said"
        titleLabel.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        headerView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Anki 听说练习"
        subtitleLabel.font = DSTheme.bodyFont(size: 12)
        headerView.addSubview(subtitleLabel)

        tableView.register(SidebarCell.self, forCellReuseIdentifier: SidebarCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.rowHeight = DSTheme.rowHeight
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(
            top: DSTheme.Spacing.sm,
            left: DSTheme.Spacing.xs,
            bottom: DSTheme.Spacing.sm,
            right: DSTheme.Spacing.xs
        )
        tableView.contentInsetAdjustmentBehavior = .never

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 82),

            logoView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            logoView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 42),
            logoView.heightAnchor.constraint(equalToConstant: 42),

            titleLabel.leadingAnchor.constraint(equalTo: logoView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.centerYAnchor, constant: 1),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),

            divider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            tableView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        SaidSection.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SidebarCell.reuseIdentifier,
            for: indexPath
        ) as? SidebarCell else {
            return UITableViewCell()
        }
        guard let section = SaidSection(rawValue: indexPath.row) else { return cell }
        cell.configure(section: section, selected: section == selectedSection)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = SaidSection(rawValue: indexPath.row) else { return }
        selectedSection = section
        tableView.reloadData()
        delegate?.sidebar(self, didSelect: section)
    }
}

private final class SidebarCell: UITableViewCell {
    static let reuseIdentifier = "SidebarCell"

    private let selectionSurface = UIView()
    private let sectionIconView = UIImageView()
    private let sectionTitleLabel = UILabel()
    private var isCurrentSection = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        selectionSurface.translatesAutoresizingMaskIntoConstraints = false
        selectionSurface.layer.cornerRadius = DSTheme.Form.cornerRadius
        sectionIconView.translatesAutoresizingMaskIntoConstraints = false
        sectionIconView.contentMode = .center
        sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionTitleLabel.font = DSTheme.titleFont(size: 15)

        contentView.addSubview(selectionSurface)
        selectionSurface.addSubview(sectionIconView)
        selectionSurface.addSubview(sectionTitleLabel)
        NSLayoutConstraint.activate([
            selectionSurface.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            selectionSurface.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionSurface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionSurface.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            sectionIconView.leadingAnchor.constraint(equalTo: selectionSurface.leadingAnchor, constant: DSTheme.Spacing.sm),
            sectionIconView.centerYAnchor.constraint(equalTo: selectionSurface.centerYAnchor),
            sectionIconView.widthAnchor.constraint(equalToConstant: 24),
            sectionIconView.heightAnchor.constraint(equalToConstant: 24),
            sectionTitleLabel.leadingAnchor.constraint(equalTo: sectionIconView.trailingAnchor, constant: DSTheme.Spacing.sm),
            sectionTitleLabel.trailingAnchor.constraint(equalTo: selectionSurface.trailingAnchor, constant: -DSTheme.Spacing.sm),
            sectionTitleLabel.centerYAnchor.constraint(equalTo: selectionSurface.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(section: SaidSection, selected: Bool) {
        isCurrentSection = selected
        sectionIconView.image = ActionIconFactory.image(section.icon, pointSize: 18)
        sectionTitleLabel.text = section.title
        applyTheme()
    }

    private func applyTheme() {
        let colors = DSTheme.c
        selectionSurface.backgroundColor = isCurrentSection ? colors.surfaceHover : .clear
        sectionIconView.tintColor = isCurrentSection ? colors.accent : colors.textSecondary
        sectionTitleLabel.textColor = isCurrentSection ? colors.textPrimary : colors.textSecondary
    }
}
