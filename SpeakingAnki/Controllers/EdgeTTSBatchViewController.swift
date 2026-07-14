import UIKit

final class EdgeTTSBatchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, ThemeRefreshable {
    private struct DeckAudioStatus {
        let deck: AnkiDeckInfo
        let textCount: Int
        let missingCount: Int
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = UILabel()
    private let queue = DispatchQueue(label: "com.said.edge-tts.batch")
    private var decks: [DeckAudioStatus] = []
    private var cancelled = false
    private var activeTask: PronounceCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "批量生成 Edge TTS"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancel))
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
        status.text = "正在统计各牌组缺少的参考音频…"
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
                    let texts = try collection.referenceTexts(inDeck: deck.id)
                    let missing = texts.filter { !EdgeTTSService.shared.hasCachedAudio(text: $0) }
                    return DeckAudioStatus(
                        deck: deck,
                        textCount: texts.count,
                        missingCount: missing.count
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let values):
                    self.decks = values
                    self.tableView.reloadData()
                    self.status.text = "选择牌组或子牌组。仅生成缺少的参考音频。"
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
        cell.detailTextLabel?.text = "参考文本 \(deck.textCount) 条 · 待生成 \(deck.missingCount) 条"
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
        status.text = "正在读取 \(deck.name) 的参考文本…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let texts = try AnkiStore.shared.requireCollection().referenceTexts(inDeck: deck.id)
                let missing = texts.filter { !EdgeTTSService.shared.hasCachedAudio(text: $0) }
                guard !missing.isEmpty else {
                    DispatchQueue.main.async {
                        self.finish("\(deck.name) 的 \(texts.count) 条参考文本均已有音频。")
                    }
                    return
                }
                self.synthesize(texts: missing, index: 0, success: 0, failures: 0, deck: deck)
            } catch {
                DispatchQueue.main.async { self.finish("读取失败：\(error.localizedDescription)") }
            }
        }
    }

    private func synthesize(
        texts: [String], index: Int, success: Int, failures: Int, deck: AnkiDeckInfo
    ) {
        guard !cancelled else {
            DispatchQueue.main.async { self.finish("已取消：成功 \(success)，失败 \(failures)") }
            return
        }
        guard index < texts.count else {
            DispatchQueue.main.async { self.finish("完成 \(deck.name)：共 \(success) 条，失败 \(failures) 条") }
            return
        }
        DispatchQueue.main.async {
            self.progress.progress = texts.isEmpty ? 1 : Float(index) / Float(texts.count)
            self.status.text = "正在生成 \(index + 1) / \(texts.count)…"
        }
        activeTask = EdgeTTSService.shared.synthesize(text: texts[index]) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                self.synthesize(
                    texts: texts,
                    index: index + 1,
                    success: success + (result.isSuccess ? 1 : 0),
                    failures: failures + (result.isSuccess ? 0 : 1),
                    deck: deck
                )
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
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
