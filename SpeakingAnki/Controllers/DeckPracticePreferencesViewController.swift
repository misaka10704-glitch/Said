import UIKit

final class DeckPracticePreferencesViewController: UIViewController, ThemeRefreshable {
    private let deckID: Int64
    private let curtain = UISwitch()
    private let centerSentence = UISwitch()
    private let sentenceSize = UISlider()

    init(deckID: Int64, deckName: String) {
        self.deckID = deckID
        super.init(nibName: nil, bundle: nil)
        title = "复习显示"
        navigationItem.prompt = deckName
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let values = DeckPracticePreferencesStore.shared.preferences(for: deckID)
        curtain.isOn = values.curtainEnabled
        centerSentence.isOn = values.centerSentence
        sentenceSize.minimumValue = 16
        sentenceSize.maximumValue = 32
        sentenceSize.value = Float(values.sentenceFontSize)
        sentenceSize.addTarget(self, action: #selector(save), for: .valueChanged)
        [curtain, centerSentence].forEach { $0.addTarget(self, action: #selector(save), for: .valueChanged) }
        let section = DSFormSection(title: "本牌组复习显示")
        section.addRow(DSFormLayout.labeledControlRow(title: "默认黑幕", control: curtain))
        section.addRow(DSFormLayout.labeledControlRow(title: "正面句子居中", control: centerSentence))
        section.addRow(DSFormLayout.labeledControlRow(title: "正面句子字号", control: sentenceSize), separated: false)
        section.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(section)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            section.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            section.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        applyTheme()
    }

    func applyTheme() {
        view.backgroundColor = DSTheme.c.background
    }

    @objc private func save() {
        DeckPracticePreferencesStore.shared.save(
            DeckPracticePreferences(
                curtainEnabled: curtain.isOn,
                centerSentence: centerSentence.isOn,
                sentenceFontSize: Double(sentenceSize.value)
            ),
            for: deckID
        )
    }
}
