import UIKit
import MobileCoreServices

final class DeckListViewController: UIViewController, ThemeRefreshable,
    UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {

    private struct Row {
        let node: DeckManagementNode
        let depth: Int
    }

    private let provider: DeckManagementDataProviding
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let summaryHeader = DeckListSummaryHeaderView()
    private let emptyState = DSEmptyStateView(
        icon: .decks,
        title: "还没有牌组",
        detail: "创建牌组或导入 APKG 后开始学习"
    )
    private let loadingIndicator = DSTheme.makeActivityIndicator()
    private let importQueue = DispatchQueue(label: "com.said.anki.deck-import", qos: .userInitiated)
    private var roots: [DeckManagementNode] = []
    private var rows: [Row] = []
    private var collapsedDeckIDs = DeckListCollapseStore.shared.collapsedDeckIDs()
    private var isImporting = false

    init(provider: DeckManagementDataProviding = OfficialDeckManagementProvider()) {
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "牌组"
        configureNavigationItems()
        configureTable()
        configureEmptyState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .saidThemeDidChange,
            object: nil
        )
        applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard tableView.tableHeaderView != nil else { return }
        let size = CGSize(width: tableView.bounds.width, height: 48)
        if tableView.tableHeaderView?.frame.size != size {
            summaryHeader.frame = CGRect(origin: .zero, size: size)
            tableView.tableHeaderView = summaryHeader
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applyTheme() {
        let colors = DSTheme.c
        view.backgroundColor = colors.background
        tableView.backgroundColor = colors.background
        tableView.separatorColor = colors.divider
        summaryHeader.applyTheme()
        emptyState.applyTheme()
        loadingIndicator.color = colors.accent
        tableView.reloadData()
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func configureNavigationItems() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        for (icon, selector, label) in [
            (ActionIconFactory.Kind.createDeck, #selector(showAddMenu(_:)), "创建牌组"),
            (ActionIconFactory.Kind.importFile, #selector(importApkg), "导入 APKG")
        ] {
            let button = UIButton(type: .system)
            let pointSize: CGFloat = icon == .importFile ? 14 : 18
            button.setImage(ActionIconFactory.image(icon, pointSize: pointSize), for: .normal)
            button.tintColor = DSTheme.c.accent
            button.accessibilityLabel = label
            button.addTarget(self, action: selector, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stack.addArrangedSubview(button)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: stack)
    }

    private func configureTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DeckTreeRowCell.self, forCellReuseIdentifier: DeckTreeRowCell.reuseIdentifier)
        tableView.rowHeight = 44
        tableView.estimatedRowHeight = 44
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 48, bottom: 0, right: 12)
        tableView.tableFooterView = UIView()
        tableView.tableHeaderView = summaryHeader
        tableView.translatesAutoresizingMaskIntoConstraints = false
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableView.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
            tableView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(750),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        emptyState.isHidden = true
    }

    private func reload() {
        loadingIndicator.startAnimating()
        provider.loadDeckTree { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadingIndicator.stopAnimating()
                switch result {
                case .success(let nodes):
                    self.roots = nodes
                    self.pruneCollapsedDeckIDs()
                    self.rebuildRows()
                    self.summaryHeader.configure(nodes: nodes)
                    self.emptyState.isHidden = !nodes.isEmpty
                case .failure(let error):
                    self.roots = []
                    self.rebuildRows()
                    self.emptyState.isHidden = false
                    self.presentAlert(error.localizedDescription)
                }
            }
        }
    }

    private func rebuildRows() {
        rows.removeAll(keepingCapacity: true)
        func append(_ nodes: [DeckManagementNode], depth: Int) {
            for node in nodes {
                rows.append(Row(node: node, depth: depth))
                if !collapsedDeckIDs.contains(node.id) {
                    append(node.children, depth: depth + 1)
                }
            }
        }
        append(roots, depth: 0)
        tableView.reloadData()
    }

    @objc private func showAddMenu(_ sender: Any) {
        SaidMenu.present(
            from: self,
            title: "添加",
            items: [
                SaidMenuItem(title: "创建顶层牌组", icon: .createDeck) { [weak self] in
                    self?.promptCreateDeck(parent: nil)
                },
                SaidMenuItem(title: "创建子牌组", icon: .createSubdeck) { [weak self] in
                    self?.showParentPickerForCreation()
                },
                SaidMenuItem(title: "导入 APKG", icon: .importFile) { [weak self] in
                    self?.importApkg()
                },
            ],
            sourceView: sender as? UIView ?? view,
            sourceRect: (sender as? UIView)?.bounds,
            preferVertical: true
        )
    }


    private func promptCreateDeck(parent: DeckManagementNode?) {
        guard parent?.filtered != true else {
            presentAlert("筛选牌组不能包含子牌组。请先选择普通牌组。")
            return
        }
        let title = parent == nil ? "创建牌组" : "创建子牌组"
        let alert = UIAlertController(
            title: title,
            message: parent.map { "父级：\($0.name)" },
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "牌组名称"
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let leaf = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !leaf.isEmpty else { return }
            let name = parent.map { "\($0.name)::\(leaf)" } ?? leaf
            self.provider.createDeck(name: name) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        if let parent = parent {
                            self.collapsedDeckIDs.remove(parent.id)
                            self.persistCollapsedDeckIDs()
                        }
                        self.reload()
                    case .failure(let error):
                        self.presentAlert(error.localizedDescription)
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func showParentPickerForCreation() {
        let choices = flattened(roots).filter { !$0.filtered }
        guard !choices.isEmpty else {
            promptCreateDeck(parent: nil)
            return
        }
        let picker = DeckParentPickerViewController(
            title: "选择父牌组",
            headerTitle: "新子牌组创建在",
            choices: choices,
            includesRoot: false
        ) { [weak self] parentID in
            guard let self = self,
                  let parentID = parentID,
                  let parent = choices.first(where: { $0.id == parentID }) else { return }
            DispatchQueue.main.async {
                self.promptCreateDeck(parent: parent)
            }
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func importApkg() {
        guard !isImporting else { return }
        let picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first else { return }
        setImporting(true)
        let accessing = source.startAccessingSecurityScopedResource()
        importQueue.async { [weak self] in
            defer {
                if accessing { source.stopAccessingSecurityScopedResource() }
            }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("said-import-\(UUID().uuidString)", isDirectory: true)
            let result: Result<SaidApkgImportResult, Error>
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let localURL = folder.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: localURL)
                let importResult = try AnkiStore.shared.importApkg(localURL)
                result = .success(importResult)
            } catch {
                result = .failure(error)
            }
            try? FileManager.default.removeItem(at: folder)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setImporting(false)
                switch result {
                case .success(let importResult):
                    self.reload()
                    self.presentAlert(importResult.formattedMessage)
                case .failure(let error):
                    self.presentAlert("导入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func setImporting(_ importing: Bool) {
        isImporting = importing
        tableView.isUserInteractionEnabled = !importing
        if importing {
            let spinner = DSTheme.makeActivityIndicator()
            spinner.startAnimating()
            navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: spinner)]
        } else {
            configureNavigationItems()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: DeckTreeRowCell.reuseIdentifier,
            for: indexPath
        ) as? DeckTreeRowCell else {
            return UITableViewCell()
        }
        cell.configure(
            node: row.node,
            depth: row.depth,
            expanded: !collapsedDeckIDs.contains(row.node.id),
            disclosureAction: { [weak self] in self?.toggle(row.node) },
            moreAction: { [weak self, weak cell] in self?.showDeckMenu(for: row.node, sourceView: cell) }
        )
        cell.applyTheme()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        startStudy(rows[indexPath.row].node)
    }

    private func toggle(_ node: DeckManagementNode) {
        guard !node.children.isEmpty else { return }
        if collapsedDeckIDs.contains(node.id) {
            collapsedDeckIDs.remove(node.id)
        } else {
            collapsedDeckIDs.insert(node.id)
        }
        persistCollapsedDeckIDs()
        rebuildRows()
    }

    private func persistCollapsedDeckIDs() {
        DeckListCollapseStore.shared.save(collapsedDeckIDs)
    }

    private func pruneCollapsedDeckIDs() {
        let validIDs = Set(flattened(roots).map(\.id))
        DeckListCollapseStore.shared.prune(keeping: validIDs)
        collapsedDeckIDs = DeckListCollapseStore.shared.collapsedDeckIDs()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let point = recognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point) else { return }
        showDeckMenu(for: rows[indexPath.row].node, sourceView: tableView.cellForRow(at: indexPath))
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let node = rows[indexPath.row].node
        let study = UIContextualAction(style: .normal, title: "学习") { [weak self] _, _, done in
            self?.startStudy(node)
            done(true)
        }
        study.image = ActionIconFactory.image(.study)
        study.backgroundColor = DSTheme.brandCyan
        guard !node.filtered else {
            let configuration = UISwipeActionsConfiguration(actions: [study])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
        let custom = UIContextualAction(style: .normal, title: "自定义") { [weak self] _, _, done in
            self?.showCustomStudy(node)
            done(true)
        }
        custom.image = ActionIconFactory.image(.customStudy)
        custom.backgroundColor = DSTheme.speakingViolet
        let configuration = UISwipeActionsConfiguration(actions: [study, custom])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func startStudy(_ node: DeckManagementNode) {
        navigationController?.pushViewController(
            ReviewViewController(deckId: node.id, deckName: node.name),
            animated: true
        )
    }

    private func showDeckMenu(for node: DeckManagementNode, sourceView: UIView?) {
        let items = node.filtered
            ? filteredDeckMenuItems(for: node, sourceView: sourceView)
            : normalDeckMenuItems(for: node, sourceView: sourceView)
        SaidMenu.present(
            from: self,
            title: node.name,
            items: items,
            sourceView: sourceView ?? view,
            sourceRect: sourceView?.bounds,
            preferVertical: true
        )
    }

    private func normalDeckMenuItems(
        for node: DeckManagementNode,
        sourceView: UIView?
    ) -> [SaidMenuItem] {
        [
            SaidMenuItem(title: "普通学习", icon: .study) { [weak self] in
                self?.startStudy(node)
            },
            SaidMenuItem(title: "自定义学习", icon: .customStudy) { [weak self] in
                self?.showCustomStudy(node)
            },
            SaidMenuItem(title: "创建子牌组", icon: .createSubdeck) { [weak self] in
                self?.promptCreateDeck(parent: node)
            },
            SaidMenuItem(title: "重命名", icon: .rename) { [weak self] in
                self?.promptRename(node)
            },
            SaidMenuItem(title: "移动到父级或根", icon: .moveDeck) { [weak self] in
                self?.showMovePicker(node)
            },
            SaidMenuItem(title: "牌组选项", icon: .deckOptions) { [weak self] in
                self?.navigationController?.pushViewController(
                    DeckOptionsViewController(deckID: node.id, provider: OfficialBrowserProvider()),
                    animated: true
                )
            },
            SaidMenuItem(title: "导出此牌组", icon: .exportDeck) { [weak self] in
                self?.showExportOptions(node, sourceView: sourceView)
            },
            SaidMenuItem(title: "删除", icon: .delete, isDestructive: true) { [weak self] in
                self?.beginDeletion(node)
            },
        ]
    }

    private func filteredDeckMenuItems(
        for node: DeckManagementNode,
        sourceView: UIView?
    ) -> [SaidMenuItem] {
        [
            SaidMenuItem(title: "学习筛选牌组", icon: .study) { [weak self] in
                self?.startStudy(node)
            },
            SaidMenuItem(title: "重新构建", icon: .rebuildFiltered) { [weak self] in
                self?.rebuildFilteredDeck(node)
            },
            SaidMenuItem(title: "清空筛选牌组", icon: .emptyFiltered) { [weak self] in
                self?.confirmEmptyFilteredDeck(node)
            },
            SaidMenuItem(title: "重命名", icon: .rename) { [weak self] in
                self?.promptRename(node)
            },
            SaidMenuItem(title: "移动到父级或根", icon: .moveDeck) { [weak self] in
                self?.showMovePicker(node)
            },
            SaidMenuItem(title: "导出此牌组", icon: .exportDeck) { [weak self] in
                self?.showExportOptions(node, sourceView: sourceView)
            },
            SaidMenuItem(title: "删除", icon: .delete, isDestructive: true) { [weak self] in
                self?.beginDeletion(node)
            },
        ]
    }

    private func rebuildFilteredDeck(_ node: DeckManagementNode) {
        provider.rebuildFilteredDeck(deckID: node.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let count):
                    self.reload()
                    self.presentAlert("筛选牌组已重新构建，共收集 \(count) 张卡片。")
                case .failure(let error):
                    self.presentAlert("重新构建筛选牌组失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func confirmEmptyFilteredDeck(_ node: DeckManagementNode) {
        let alert = UIAlertController(
            title: "清空筛选牌组？",
            message: "卡片会返回各自的原牌组，不会被删除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            self?.emptyFilteredDeck(node)
        })
        present(alert, animated: true)
    }

    private func emptyFilteredDeck(_ node: DeckManagementNode) {
        provider.emptyFilteredDeck(deckID: node.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.reload()
                    self.presentAlert("筛选牌组已清空，卡片已返回原牌组。")
                case .failure(let error):
                    self.presentAlert("清空筛选牌组失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func showCustomStudy(_ node: DeckManagementNode) {
        guard !node.filtered else {
            presentAlert("筛选牌组不支持自定义学习；请使用“重新构建”或“清空筛选牌组”。")
            return
        }
        navigationController?.pushViewController(
            DeckCustomStudyViewController(deck: node, provider: provider),
            animated: true
        )
    }

    private func promptRename(_ node: DeckManagementNode) {
        let parts = node.name.components(separatedBy: "::")
        let alert = UIAlertController(
            title: "重命名牌组",
            message: parts.count > 1 ? "只修改当前层级名称；父级保持不变" : nil,
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = parts.last
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let leaf = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !leaf.isEmpty else { return }
            let newName = (Array(parts.dropLast()) + [leaf]).joined(separator: "::")
            self.provider.renameDeck(deckID: node.id, newName: newName) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self.reload()
                    case .failure(let error): self.presentAlert(error.localizedDescription)
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func showMovePicker(_ node: DeckManagementNode) {
        let excluded = Set(flattened([node]).map(\.id))
        let choices = flattened(roots).filter {
            !excluded.contains($0.id) && !$0.filtered
        }
        let picker = DeckParentPickerViewController(
            title: "移动牌组",
            headerTitle: "移动“\(node.name)”到",
            choices: choices,
            includesRoot: true
        ) { [weak self] parentID in
            guard let self = self else { return }
            self.provider.reparentDecks(deckIDs: [node.id], newParentID: parentID) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self.reload()
                    case .failure(let error): self.presentAlert(error.localizedDescription)
                    }
                }
            }
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func showExportOptions(_ node: DeckManagementNode, sourceView: UIView?) {
        SaidMenu.present(
            from: self,
            title: "导出 \(node.name)",
            items: [
                SaidMenuItem(title: "换机导出（无媒体）", icon: .exportDeck) { [weak self] in
                    self?.exportDeck(node, options: .deviceMigration(deckID: node.id))
                },
                SaidMenuItem(title: "包含学习进度", icon: .exportWithScheduling) { [weak self] in
                    self?.exportDeck(
                        node,
                        options: .desktopSync(deckID: node.id, includeScheduling: true)
                    )
                },
                SaidMenuItem(title: "不含学习进度", icon: .exportWithoutScheduling) { [weak self] in
                    self?.exportDeck(
                        node,
                        options: .desktopSync(deckID: node.id, includeScheduling: false)
                    )
                },
            ],
            sourceView: sourceView ?? view,
            sourceRect: sourceView?.bounds,
            preferAbove: true,
            preferVertical: true
        )
    }

    private func exportDeck(_ node: DeckManagementNode, options: SaidApkgExportOptions) {
        let safeName = node.name
            .replacingOccurrences(of: "::", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let suffix = options.profile == .deviceMigration ? "_migration" : ""
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)\(suffix).apkg")
        try? FileManager.default.removeItem(at: url)
        provider.exportDeck(
            deckID: node.id,
            to: url,
            options: options
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    activity.popoverPresentationController?.sourceView = self.view
                    activity.popoverPresentationController?.sourceRect = CGRect(
                        x: self.view.bounds.midX,
                        y: self.view.bounds.midY,
                        width: 1,
                        height: 1
                    )
                    self.present(activity, animated: true)
                case .failure(let error):
                    self.presentAlert("导出失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func beginDeletion(_ node: DeckManagementNode) {
        provider.previewDeletion(deckIDs: [node.id]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let preview):
                    self.showDeletionPreview(node: node, preview: preview)
                case .failure(let error):
                    self.presentAlert(error.localizedDescription)
                }
            }
        }
    }

    private func showDeletionPreview(node: DeckManagementNode, preview: DeckDeletionPreview) {
        let message = """
        将删除 \(preview.affectedDeckCount) 个牌组，预计 \(preview.estimatedDeletedCardCount) 张卡片。

        删除普通牌组中的卡片后，失去最后一张卡片的孤儿笔记也会被删除。操作前会同步创建安全备份。
        """
        let alert = UIAlertController(title: "检查删除影响", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
            self?.confirmDeletion(node: node, preview: preview)
        })
        present(alert, animated: true)
    }

    private func confirmDeletion(node: DeckManagementNode, preview: DeckDeletionPreview) {
        let alert = UIAlertController(
            title: "再次确认删除",
            message: "输入完整牌组名“\(node.name)”以确认。",
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = node.name
            $0.autocorrectionType = .no
            $0.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        let deleteAction = UIAlertAction(title: "永久删除", style: .destructive) { [weak self, weak alert] _ in
            guard alert?.textFields?.first?.text == node.name else {
                self?.presentAlert("牌组名不匹配，未执行删除。")
                return
            }
            self?.performDeletion(node: node)
        }
        alert.addAction(deleteAction)
        present(alert, animated: true)
    }

    private func performDeletion(node: DeckManagementNode) {
        provider.deleteDecks(deckIDs: [node.id]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let deletion):
                    self.reload()
                    let backup = deletion.backupCreated ? "已创建安全备份。" : ""
                    let message = "已删除 \(deletion.deletedCardCount) 张卡片。\(backup)"
                    let alert = UIAlertController(title: "牌组已删除", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "撤销删除", style: .default) { [weak self] _ in
                        self?.undoDeletion()
                    })
                    alert.addAction(UIAlertAction(title: "完成", style: .cancel))
                    self.present(alert, animated: true)
                case .failure(let error):
                    self.presentAlert("删除失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func undoDeletion() {
        provider.undoLastOperation { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.reload()
                    self.presentAlert("已撤销删除")
                case .failure(let error):
                    self.presentAlert("撤销失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func flattened(_ nodes: [DeckManagementNode]) -> [DeckManagementNode] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }

    private func presentAlert(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
