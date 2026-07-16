import UIKit

final class TranslationBatchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, ThemeRefreshable {
    private struct DeckTranslationStatus {
        let deck: AnkiDeckInfo
        let noteCount: Int
        let missingCount: Int
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = UILabel()
    private let queue = DispatchQueue(label: "com.said.translation.batch")
    private var decks: [DeckTranslationStatus] = []
    private var cancelled = false
    private var activeTask: PronounceCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "批量翻译中文"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "取消", style: .plain, target: self, action: #selector(cancel)
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        status.font = DSTheme.bodyFont(size: 13)
        status.numberOfLines = 0
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        view.addSubview(progress)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: progress.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: progress.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        status.text = "正在统计各牌组缺少中文译文的笔记…"
        loadDecks()
        applyTheme()
    }

    func applyTheme() {
        view.backgroundColor = DSTheme.c.background
        tableView.backgroundColor = DSTheme.c.background
        tableView.separatorColor = DSTheme.c.divider
        status.textColor = DSTheme.c.textSecondary
        progress.progressTintColor = DSTheme.c.accent
    }

    private func loadDecks() {
        queue.async { [weak self] in
            let result = Result {
                let collection = try AnkiStore.shared.requireCollection()
                return try collection.listDecks().map { deck in
                    let summary = try collection.translationSummary(inDeck: deck.id)
                    return DeckTranslationStatus(
                        deck: deck,
                        noteCount: summary.total,
                        missingCount: summary.missing
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let values):
                    self.decks = values
                    self.tableView.reloadData()
                    self.status.text = "选择牌组。仅翻译本 App 新增的卡片（标签 trans）。"
                case .failure(let error):
                    self.status.text = "统计失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { decks.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let deck = decks[indexPath.row]
        cell.textLabel?.text = deck.deck.name
        if deck.noteCount > 0, deck.missingCount == 0 {
            cell.detailTextLabel?.text = "已标记 \(deck.noteCount) 条 · 可翻译 0 条（已有中文或字段不匹配）"
        } else {
            cell.detailTextLabel?.text = "已标记 \(deck.noteCount) 条 · 可翻译 \(deck.missingCount) 条"
        }
        cell.textLabel?.textColor = DSTheme.c.textPrimary
        cell.detailTextLabel?.textColor = DSTheme.c.textSecondary
        cell.backgroundColor = DSTheme.c.background
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        start(deck: decks[indexPath.row].deck)
    }

    private func start(deck: AnkiDeckInfo) {
        tableView.isUserInteractionEnabled = false
        cancelled = false
        progress.progress = 0
        status.text = "正在读取 \(deck.name) 的待翻译笔记…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let collection = try AnkiStore.shared.requireCollection()
                let candidates = try collection.translationCandidates(inDeck: deck.id)
                guard !candidates.isEmpty else {
                    let summary = try collection.translationSummary(inDeck: deck.id)
                    let message: String
                    if summary.total > 0 {
                        message = "\(deck.name)：找到 \(summary.total) 条 trans 标签，但均已有中文或字段无法写入。"
                    } else {
                        message = "\(deck.name) 没有带 trans 标签的本 App 新增卡片。"
                    }
                    DispatchQueue.main.async {
                        self.finish(message)
                    }
                    return
                }
                self.translate(
                    candidates: candidates,
                    index: 0,
                    success: 0,
                    failures: 0,
                    deck: deck
                )
            } catch {
                DispatchQueue.main.async { self.finish("读取失败：\(error.localizedDescription)") }
            }
        }
    }

    private func translate(
        candidates: [TranslationNoteCandidate],
        index: Int,
        success: Int,
        failures: Int,
        deck: AnkiDeckInfo
    ) {
        guard !cancelled else {
            DispatchQueue.main.async { self.finish("已取消：成功 \(success)，失败 \(failures)") }
            return
        }
        guard index < candidates.count else {
            DispatchQueue.main.async {
                self.finish("完成 \(deck.name)：共 \(success) 条，失败 \(failures) 条")
            }
            return
        }

        let candidate = candidates[index]
        DispatchQueue.main.async {
            self.progress.progress = candidates.isEmpty ? 1 : Float(index) / Float(candidates.count)
            self.status.text = "正在翻译 \(index + 1) / \(candidates.count)…"
        }

        activeTask = TranslationService.shared.translate(text: candidate.sourceText) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                switch result {
                case .success(let translation):
                    do {
                        try AnkiStore.shared.requireCollection().applyTranslation(
                            noteID: candidate.noteID,
                            targetFieldIndex: candidate.targetFieldIndex,
                            translation: translation
                        )
                        self.translate(
                            candidates: candidates,
                            index: index + 1,
                            success: success + 1,
                            failures: failures,
                            deck: deck
                        )
                    } catch {
                        self.translate(
                            candidates: candidates,
                            index: index + 1,
                            success: success,
                            failures: failures + 1,
                            deck: deck
                        )
                    }
                case .failure:
                    self.translate(
                        candidates: candidates,
                        index: index + 1,
                        success: success,
                        failures: failures + 1,
                        deck: deck
                    )
                }
            }
        }
    }

    @objc private func cancel() {
        cancelled = true
        activeTask?.cancel()
    }

    private func finish(_ text: String) {
        activeTask = nil
        tableView.isUserInteractionEnabled = true
        progress.progress = 1
        status.text = text
        loadDecks()
    }
}
