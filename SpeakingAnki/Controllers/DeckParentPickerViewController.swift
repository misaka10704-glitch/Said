import UIKit

final class DeckParentPickerViewController: UITableViewController, ThemeRefreshable {
    private let screenTitle: String
    private let headerTitle: String
    private let choices: [DeckManagementNode]
    private let includesRoot: Bool
    private let selection: (Int64?) -> Void

    init(
        title: String,
        headerTitle: String,
        choices: [DeckManagementNode],
        includesRoot: Bool,
        selection: @escaping (Int64?) -> Void
    ) {
        self.screenTitle = title
        self.headerTitle = headerTitle
        self.choices = choices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        self.includesRoot = includesRoot
        self.selection = selection
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        tableView.rowHeight = DSTheme.List.rowHeight
        tableView.tableFooterView = UIView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .saidThemeDidChange,
            object: nil
        )
        applyTheme()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applyTheme() {
        view.backgroundColor = DSTheme.c.background
        tableView.backgroundColor = DSTheme.c.background
        tableView.separatorColor = DSTheme.c.divider
        tableView.reloadData()
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        choices.count + (includesRoot ? 1 : 0)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        headerTitle
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "ParentChoiceCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        cell.backgroundColor = DSTheme.c.background
        cell.textLabel?.textColor = DSTheme.c.textPrimary
        cell.detailTextLabel?.textColor = DSTheme.c.textTertiary
        cell.accessoryType = .disclosureIndicator
        if includesRoot && indexPath.row == 0 {
            cell.textLabel?.text = "移到根级"
            cell.detailTextLabel?.text = "不使用父牌组"
        } else {
            let choice = choices[indexPath.row - (includesRoot ? 1 : 0)]
            cell.textLabel?.text = choice.name
            cell.detailTextLabel?.text = "\(choice.totalIncludingChildren) 张卡片"
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let parentID: Int64?
        if includesRoot && indexPath.row == 0 {
            parentID = nil
        } else {
            parentID = choices[indexPath.row - (includesRoot ? 1 : 0)].id
        }
        selection(parentID)
        navigationController?.popViewController(animated: true)
    }
}
