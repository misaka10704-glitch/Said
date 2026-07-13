import UIKit

final class BrowserViewController: UIViewController, ThemeRefreshable {
  private let provider: BrowserDataProviding
  private let pageSize: Int
  private let searchBar = UISearchBar()
  private let deckButton = UIButton(type: .system)
  private let tableView = UITableView(frame: .zero, style: .plain)
  private let actionBar = UIScrollView()
  private let actionStack = UIStackView()
  private let statusLabel = UILabel()

  private var cards: [BrowserCardRow] = []
  private var nextCursor: String?
  private var isLoading = false
  private var totalCount = 0
  private var deckChoices: [BrowserDeckChoice] = []
  private var selectedDeckID: Int64?

  init(provider: BrowserDataProviding, pageSize: Int = 50) {
    self.provider = provider
    self.pageSize = pageSize
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "浏览"
    configureViews()
    applyTheme()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
    loadDeckChoices()
    loadFirstPage()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureViews() {
    navigationItem.rightBarButtonItem = editButtonItem
    searchBar.delegate = self
    searchBar.placeholder = "搜索卡片、标签或牌组"
    searchBar.autocapitalizationType = .none
    searchBar.autocorrectionType = .no
    searchBar.translatesAutoresizingMaskIntoConstraints = false

    deckButton.setTitle("全部牌组 ▾", for: .normal)
    deckButton.titleLabel?.font = DSTheme.bodyFont(size: 14)
    deckButton.contentHorizontalAlignment = .left
    deckButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
    deckButton.addTarget(self, action: #selector(chooseBrowseDeck), for: .touchUpInside)
    deckButton.translatesAutoresizingMaskIntoConstraints = false

    tableView.dataSource = self
    tableView.delegate = self
    tableView.allowsMultipleSelectionDuringEditing = true
    tableView.keyboardDismissMode = .onDrag
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 66
    tableView.register(
      BrowserCardCell.self, forCellReuseIdentifier: BrowserCardCell.reuseIdentifier)
    tableView.translatesAutoresizingMaskIntoConstraints = false

    actionBar.translatesAutoresizingMaskIntoConstraints = false
    actionBar.showsHorizontalScrollIndicator = false
    actionStack.axis = .horizontal
    actionStack.alignment = .center
    actionStack.spacing = 8
    actionStack.translatesAutoresizingMaskIntoConstraints = false
    actionBar.addSubview(actionStack)

    let actions: [(String, Selector)] = [
      ("暂停", #selector(suspendSelected)),
      ("搁置", #selector(burySelected)),
      ("标记", #selector(flagSelected)),
      ("删除", #selector(deleteSelected)),
      ("移动", #selector(moveSelected)),
      ("标签", #selector(tagSelected)),
    ]
    for (title, selector) in actions {
      let button = UIButton(type: .system)
      button.setTitle(title, for: .normal)
      button.titleLabel?.font = DSTheme.titleFont(size: 14)
      button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
      button.layer.cornerRadius = 8
      button.addTarget(self, action: selector, for: .touchUpInside)
      actionStack.addArrangedSubview(button)
    }

    statusLabel.font = DSTheme.bodyFont(size: 15)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(searchBar)
    view.addSubview(deckButton)
    view.addSubview(tableView)
    view.addSubview(actionBar)
    view.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      searchBar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
      searchBar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
      searchBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      searchBar.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      searchBar.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(750),
      searchBar.heightAnchor.constraint(equalToConstant: 48),
      deckButton.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
      deckButton.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
      deckButton.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),
      deckButton.heightAnchor.constraint(equalToConstant: 36),
      actionBar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
      actionBar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
      actionBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      actionBar.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      actionBar.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(750),
      actionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      actionBar.heightAnchor.constraint(equalToConstant: 54),
      actionStack.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 12),
      actionStack.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -12),
      actionStack.topAnchor.constraint(equalTo: actionBar.topAnchor),
      actionStack.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor),
      actionStack.heightAnchor.constraint(equalTo: actionBar.heightAnchor),
      tableView.topAnchor.constraint(equalTo: deckButton.bottomAnchor),
      tableView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
      tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      tableView.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      tableView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(750),
      tableView.bottomAnchor.constraint(equalTo: actionBar.topAnchor),
      statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
    setEditing(false, animated: false)
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    searchBar.barStyle = colors.navBarStyle
    searchBar.barTintColor = colors.surface
    searchBar.tintColor = colors.accent
    deckButton.backgroundColor = colors.surface
    deckButton.setTitleColor(colors.accent, for: .normal)
    tableView.backgroundColor = colors.background
    tableView.separatorColor = colors.divider
    actionBar.backgroundColor = colors.surface
    statusLabel.textColor = colors.textSecondary
    for button in actionStack.arrangedSubviews.compactMap({ $0 as? UIButton }) {
      button.backgroundColor = colors.surfaceHover
      button.setTitleColor(
        button.currentTitle == "删除" ? colors.destructive : colors.accent,
        for: .normal
      )
    }
    for cell in tableView.visibleCells.compactMap({ $0 as? BrowserCardCell }) {
      cell.applyTheme()
    }
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  override func setEditing(_ editing: Bool, animated: Bool) {
    super.setEditing(editing, animated: animated)
    tableView.setEditing(editing, animated: animated)
    actionBar.isHidden = !editing
    updateSelectionTitle()
  }

  private func loadDeckChoices() {
    provider.fetchDeckChoices { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self, case .success(let choices) = result else { return }
        self.deckChoices = choices
        if let selected = self.selectedDeckID,
          !choices.contains(where: { $0.id == selected })
        {
          self.selectedDeckID = nil
          self.updateBrowseDeckTitle()
          self.loadFirstPage()
        }
      }
    }
  }

  @objc private func chooseBrowseDeck() {
    var items = [
      SaidMenuItem(
        title: "全部牌组",
        icon: .decks,
        isSelected: selectedDeckID == nil
      ) { [weak self] in self?.selectBrowseDeck(nil) }
    ]
    items.append(contentsOf: deckChoices.map { deck in
      SaidMenuItem(
        title: deck.name,
        icon: .decks,
        isSelected: selectedDeckID == deck.id
      ) { [weak self] in self?.selectBrowseDeck(deck.id) }
    })
    SaidMenu.present(
      from: self,
      title: "浏览牌组",
      items: items,
      sourceView: deckButton,
      preferVertical: true
    )
  }

  private func selectBrowseDeck(_ deckID: Int64?) {
    guard selectedDeckID != deckID else { return }
    selectedDeckID = deckID
    updateBrowseDeckTitle()
    loadFirstPage()
  }

  private func updateBrowseDeckTitle() {
    let name = selectedDeckID.flatMap { selected in
      deckChoices.first(where: { $0.id == selected })?.name
    } ?? "全部牌组"
    deckButton.setTitle("\(name) ▾", for: .normal)
  }

  private var browserQuery: String {
    var clauses: [String] = []
    if let selected = selectedDeckID,
      let name = deckChoices.first(where: { $0.id == selected })?.name
    {
      let escaped = name
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      clauses.append("deck:\"\(escaped)\"")
    }
    let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { clauses.append(text) }
    return clauses.joined(separator: " ")
  }

  private func loadFirstPage() {
    cards = []
    nextCursor = nil
    totalCount = 0
    tableView.reloadData()
    fetchPage(cursor: nil)
  }

  private func fetchPage(cursor: String?) {
    guard !isLoading else { return }
    isLoading = true
    statusLabel.text = cards.isEmpty ? "正在载入…" : nil
    provider.fetchCards(matching: browserQuery, cursor: cursor, pageSize: pageSize) {
      [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isLoading = false
        switch result {
        case .success(let page):
          self.cards.append(contentsOf: page.cards)
          self.nextCursor = page.nextCursor
          self.totalCount = page.totalCount
          self.statusLabel.text = self.cards.isEmpty ? "没有找到卡片" : nil
          self.tableView.reloadData()
          self.updateSelectionTitle()
        case .failure(let error):
          self.statusLabel.text = error.localizedDescription
        }
      }
    }
  }

  @objc private func runSearch() {
    loadFirstPage()
  }

  private var selectedCardIDs: [Int64] {
    let paths = tableView.indexPathsForSelectedRows ?? []
    return paths.compactMap { $0.row < cards.count ? cards[$0.row].cardID : nil }
  }

  private func updateSelectionTitle() {
    guard isEditing else {
      title = totalCount > 0 ? "浏览（\(totalCount)）" : "浏览"
      return
    }
    title = "已选择 \(selectedCardIDs.count) 张"
  }

  private func perform(_ action: BrowserCardAction) {
    let ids = selectedCardIDs
    guard !ids.isEmpty else {
      showAlert("请至少选择一张卡片。")
      return
    }
    provider.perform(action: action, cardIDs: ids) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          self?.setEditing(false, animated: true)
          self?.loadFirstPage()
        case .failure(let error):
          self?.showAlert(error.localizedDescription)
        }
      }
    }
  }

  @objc private func suspendSelected() { perform(.suspend) }
  @objc private func burySelected() { perform(.bury) }

  @objc private func flagSelected(_ sender: UIButton) {
    let items = (0...7).map { flag in
      SaidMenuItem(title: flag == 0 ? "无标记" : "标记 \(flag)", icon: .browse) {
        [weak self] in
        self?.perform(.flag(flag))
      }
    }
    SaidMenu.present(
      from: self,
      title: "设置标记",
      items: items,
      sourceView: sender,
      preferAbove: true,
      preferVertical: true
    )
  }

  @objc private func deleteSelected() {
    guard !selectedCardIDs.isEmpty else {
      showAlert("请至少选择一张卡片。")
      return
    }
    let alert = UIAlertController(
      title: "删除所选笔记？",
      message: "属于这些笔记的全部卡片都会被删除。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
        self?.perform(.delete)
      })
    present(alert, animated: true)
  }

  @objc private func moveSelected(_ sender: UIButton) {
    guard !selectedCardIDs.isEmpty else {
      showAlert("请至少选择一张卡片。")
      return
    }
    provider.fetchDeckChoices { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success(let decks):
          let items = decks.map { deck in
            SaidMenuItem(title: deck.name, icon: .decks) { [weak self] in
              self?.perform(.move(deckID: deck.id))
            }
          }
          SaidMenu.present(
            from: self,
            title: "移动到牌组",
            items: items,
            sourceView: sender,
            preferAbove: true,
            preferVertical: true
          )
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  @objc private func tagSelected() {
    guard !selectedCardIDs.isEmpty else {
      showAlert("请至少选择一张卡片。")
      return
    }
    let alert = UIAlertController(title: "添加标签", message: "多个标签请用空格分隔。", preferredStyle: .alert)
    alert.addTextField { $0.placeholder = "important language::speaking" }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "添加", style: .default) { [weak self, weak alert] _ in
        let tags = (alert?.textFields?.first?.text ?? "")
          .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tags.isEmpty else { return }
        self?.perform(.addTags(tags))
      })
    present(alert, animated: true)
  }

  private func showAlert(_ message: String) {
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }
}

extension BrowserViewController: UISearchBarDelegate {
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    NSObject.cancelPreviousPerformRequests(
      withTarget: self, selector: #selector(runSearch), object: nil)
    perform(#selector(runSearch), with: nil, afterDelay: 0.35)
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    NSObject.cancelPreviousPerformRequests(
      withTarget: self, selector: #selector(runSearch), object: nil)
    searchBar.resignFirstResponder()
    loadFirstPage()
  }
}

extension BrowserViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return cards.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell =
      tableView.dequeueReusableCell(
        withIdentifier: BrowserCardCell.reuseIdentifier,
        for: indexPath
      ) as! BrowserCardCell
    cell.configure(with: cards[indexPath.row])
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if isEditing {
      updateSelectionTitle()
    } else {
      tableView.deselectRow(at: indexPath, animated: true)
      guard let editorProvider = provider as? NoteEditorDataProviding else {
        showAlert("当前集合无法编辑笔记。")
        return
      }
      navigationController?.pushViewController(
        NoteEditorViewController(
          noteID: cards[indexPath.row].noteID,
          provider: editorProvider
        ),
        animated: true
      )
    }
  }

  func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
    if isEditing { updateSelectionTitle() }
  }

  func tableView(
    _ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath
  ) {
    if indexPath.row >= cards.count - 8, let cursor = nextCursor {
      fetchPage(cursor: cursor)
    }
  }
}

private final class BrowserCardCell: UITableViewCell {
  static let reuseIdentifier = "BrowserCardCell"
  private let frontLabel = UILabel()
  private let backLabel = UILabel()
  private let metadataLabel = UILabel()
  private let badgeLabel = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    let stack = UIStackView(arrangedSubviews: [frontLabel, backLabel, metadataLabel])
    stack.axis = .vertical
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    badgeLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)
    contentView.addSubview(badgeLabel)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -12),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
      badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      badgeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      badgeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 90),
    ])
    frontLabel.font = DSTheme.titleFont(size: 16)
    backLabel.font = DSTheme.bodyFont(size: 14)
    metadataLabel.font = DSTheme.bodyFont(size: 12)
    badgeLabel.font = DSTheme.titleFont(size: 11)
    badgeLabel.textAlignment = .right
    for label in [frontLabel, backLabel, metadataLabel] { label.numberOfLines = 1 }
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(with card: BrowserCardRow) {
    frontLabel.text = card.front
    backLabel.text = card.back
    metadataLabel.text = "\(card.deckName) · \(card.templateName) · \(card.dueText)"
    if card.isSuspended {
      badgeLabel.text = "已暂停"
    } else if card.isBuried {
      badgeLabel.text = "已搁置"
    } else if card.flag > 0 {
      badgeLabel.text = "标记 \(card.flag)"
    } else {
      badgeLabel.text = card.tags.prefix(2).joined(separator: " ")
    }
  }

  func applyTheme() {
    let colors = DSTheme.c
    backgroundColor = colors.background
    contentView.backgroundColor = colors.background
    frontLabel.textColor = colors.textPrimary
    backLabel.textColor = colors.textSecondary
    metadataLabel.textColor = colors.textTertiary
    badgeLabel.textColor = colors.accent
    tintColor = colors.accent
  }
}
