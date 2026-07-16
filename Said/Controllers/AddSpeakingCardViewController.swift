import UIKit
import SaidAnkiBackend

/// Minimal, deck-scoped note entry. Deck and template are deliberately chosen
/// once in the deck options screen instead of repeating them per card.
final class AddSpeakingCardViewController: UIViewController, ThemeRefreshable {
    private let deckID: Int64
    private let deckName: String
    private let queue = DispatchQueue(label: "com.said.anki.add-card")
    private let contentField = DSTextField(placeholder: "输入单词、短语或句子")
    private let templateLabel = UILabel()
    private let saveButton = DSButton(style: .primary)
    private var selectedType: SaidNotetype?

    init(deckID: Int64, deckName: String) {
        self.deckID = deckID
        self.deckName = deckName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "添加卡片"
        build()
        loadTemplate()
    }

    func applyTheme() {
        view.backgroundColor = DSTheme.c.background
        contentField.applyTheme()
        saveButton.applyTheme()
        templateLabel.textColor = DSTheme.c.textSecondary
    }

    private func build() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        let destination = DSFormSection(title: deckName, detail: "内容会直接添加到此牌组。")
        templateLabel.font = DSTheme.bodyFont(size: 13)
        templateLabel.numberOfLines = 0
        templateLabel.text = "正在读取牌组模板…"
        destination.addRow(templateLabel, separated: false)
        stack.addArrangedSubview(destination)

        let entry = DSFormSection(title: "内容")
        entry.addRow(contentField, separated: false)
        stack.addArrangedSubview(entry)

        saveButton.setTitle("添加到此牌组", for: .normal)
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        saveButton.isEnabled = false
        stack.addArrangedSubview(saveButton)
        applyTheme()
    }

    private func loadTemplate() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let result = Result { () -> SaidNotetype in
                let collection = try AnkiStore.shared.requireCollection()
                let types = try collection.allNoteTypes()
                let configuredID = DeckPracticePreferencesStore.shared.preferences(for: self.deckID).noteTypeID
                guard let type = types.first(where: { $0.id == configuredID })
                    ?? types.first(where: { $0.name.lowercased().contains("words") || $0.name.contains("生词") })
                    ?? types.first else {
                    throw AnkiError.notFound
                }
                return type
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let type):
                    self.selectedType = type
                    self.templateLabel.text = "模板：\(type.name)"
                    self.saveButton.isEnabled = true
                case .failure:
                    self.templateLabel.text = "未设置可用模板。请返回“牌组选项”设置卡片模板。"
                }
            }
        }
    }

    @objc private func save() {
        guard let type = selectedType else { return }
        let content = contentField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            showMessage("请输入单词、短语或句子。")
            return
        }
        guard let primaryIndex = NoteFieldMapper.primaryContentFieldIndex(in: type.fieldNames) else {
            showMessage("模板没有可识别的内容字段。请在“牌组选项”换一个模板。")
            return
        }
        var values = Array(repeating: "", count: type.fieldNames.count)
        values[primaryIndex] = content
        saveButton.isEnabled = false
        queue.async { [weak self] in
            let result = Result {
                try AnkiStore.shared.requireCollection().addNote(
                    deckID: self?.deckID ?? 0,
                    notetypeID: type.id,
                    fields: values,
                    tags: [SaidNoteTags.needsTranslation]
                )
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success:
                    self.contentField.text = ""
                    self.showMessage("已添加到 \(self.deckName)")
                case .failure(let error):
                    self.showMessage(error.localizedDescription)
                }
            }
        }
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
