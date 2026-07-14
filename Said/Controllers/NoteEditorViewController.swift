import MobileCoreServices
import UIKit

final class NoteEditorViewController: UIViewController, UIDocumentPickerDelegate, ThemeRefreshable {
  private let noteID: Int64
  private let provider: NoteEditorDataProviding
  private let scrollView = UIScrollView()
  private let contentStack = UIStackView()
  private var contentMaxWidthConstraint: NSLayoutConstraint?
  private let fieldsStack = UIStackView()
  private let tagsField = DSTextField(placeholder: "标签一 嵌套::标签")
  private let modelLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .gray)
  private let mediaButton = DSButton(style: .secondary)
  private let recordButton = DSButton(style: .secondary)
  private let toolRow = UIStackView()
  private let tagsSection = DSFormSection(title: "标签")
  private let mediaSection = DSFormSection(title: "媒体")

  private var note: EditableNote?
  private var fieldEditors: [UITextView] = []
  private var sectionLabels: [UILabel] = []
  private var activeFieldIndex = 0
  private let recorder = AudioRecorder()

  init(noteID: Int64, provider: NoteEditorDataProviding) {
    self.noteID = noteID
    self.provider = provider
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "编辑笔记"
    configureViews()
    applyTheme()
    observeKeyboard()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
    loadNote()
  }

  deinit {
    recorder.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  private func configureViews() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "保存",
      style: .done,
      target: self,
      action: #selector(save)
    )
    navigationItem.rightBarButtonItem?.isEnabled = false

    scrollView.keyboardDismissMode = .interactive
    scrollView.alwaysBounceVertical = true
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.spacing = 16
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    fieldsStack.axis = .vertical
    fieldsStack.spacing = 14

    modelLabel.font = DSTheme.bodyFont(size: 13)
    modelLabel.numberOfLines = 0
    let infoSection = DSFormSection(title: "笔记类型")
    infoSection.addRow(modelLabel, separated: false)
    contentStack.addArrangedSubview(infoSection)
    contentStack.addArrangedSubview(fieldsStack)

    tagsField.autocapitalizationType = .none
    tagsField.autocorrectionType = .no
    tagsSection.addRow(tagsField, separated: false)
    contentStack.addArrangedSubview(tagsSection)

    toolRow.addArrangedSubview(mediaButton)
    toolRow.addArrangedSubview(recordButton)
    toolRow.axis = .horizontal
    toolRow.spacing = 12
    toolRow.distribution = .fillEqually
    configureToolButton(mediaButton, title: "添加文件", selector: #selector(addMedia))
    configureToolButton(recordButton, title: "录制音频", selector: #selector(recordAudio))
    mediaSection.addRow(toolRow, separated: false)
    contentStack.addArrangedSubview(mediaSection)

    activityIndicator.hidesWhenStopped = true
    contentStack.addArrangedSubview(activityIndicator)

    view.addSubview(scrollView)
    scrollView.addSubview(contentStack)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      contentStack.topAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DSTheme.contentPadding),
      contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: scrollView.contentLayoutGuide.leadingAnchor,
        constant: DSTheme.contentPadding),
      contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: scrollView.contentLayoutGuide.trailingAnchor,
        constant: -DSTheme.contentPadding),
      contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
      contentStack.bottomAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DSTheme.contentPadding),
      contentStack.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -DSTheme.contentPadding * 2
      ),
    ])
    contentMaxWidthConstraint = contentStack.widthAnchor.constraint(
      lessThanOrEqualToConstant: DSTheme.contentMaxWidth)
    contentMaxWidthConstraint?.isActive = true
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Editing text on an iPad should use the available horizontal workspace
    // instead of keeping phone-sized fields centred in a wide landscape view.
    let windowBounds = view.window?.bounds ?? UIScreen.main.bounds
    let availableWidth = max(0, view.bounds.width - DSTheme.contentPadding * 2)
    contentMaxWidthConstraint?.constant = windowBounds.width > windowBounds.height
      ? availableWidth
      : min(DSTheme.contentMaxWidth, availableWidth)
  }

  private func configureToolButton(_ button: DSButton, title: String, selector: Selector) {
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = DSTheme.titleFont(size: 15)
    button.addTarget(self, action: selector, for: .touchUpInside)
    button.isEnabled = false
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    scrollView.backgroundColor = colors.background
    modelLabel.textColor = colors.textSecondary
    for label in sectionLabels { label.textColor = colors.textSecondary }
    tagsSection.applyTheme()
    mediaSection.applyTheme()
    tagsField.applyTheme()
    for editor in fieldEditors {
      editor.backgroundColor = colors.inputBackground
      editor.textColor = colors.textPrimary
      editor.layer.borderColor = colors.inputBorder.cgColor
      editor.keyboardAppearance = ThemeManager.shared.mode == .dark ? .dark : .light
    }
    for button in [mediaButton, recordButton] { button.applyTheme() }
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  private func loadNote() {
    setBusy(true)
    provider.loadNote(noteID: noteID) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.setBusy(false)
        switch result {
        case .success(let note):
          self.note = note
          self.render(note)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  private func render(_ note: EditableNote) {
    modelLabel.text = note.modelName
    tagsField.text = note.tags.joined(separator: " ")
    fieldEditors = []
    for subview in fieldsStack.arrangedSubviews {
      fieldsStack.removeArrangedSubview(subview)
      subview.removeFromSuperview()
    }
    for (index, field) in note.fields.enumerated() {
      let container = DSFormSection(title: field.name)

      let editor = UITextView()
      editor.delegate = self
      editor.tag = index
      editor.text = field.value
      editor.font = DSTheme.bodyFont(size: 16)
      editor.backgroundColor = DSTheme.c.inputBackground
      editor.textColor = DSTheme.c.textPrimary
      editor.layer.borderWidth = 1
      editor.layer.borderColor = DSTheme.c.inputBorder.cgColor
      editor.layer.cornerRadius = 10
      editor.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
      // Let the outer editor page scroll; a scrollable text view nested inside
      // it makes long fields feel cramped and difficult to read on iPad.
      editor.isScrollEnabled = false
      editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
      container.addRow(editor, separated: false)
      fieldsStack.addArrangedSubview(container)
      fieldEditors.append(editor)
    }
    navigationItem.rightBarButtonItem?.isEnabled = true
    mediaButton.isEnabled = !fieldEditors.isEmpty
    recordButton.isEnabled = !fieldEditors.isEmpty
  }

  private func makeSectionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DSTheme.titleFont(size: 14)
    label.textColor = DSTheme.c.textSecondary
    sectionLabels.append(label)
    return label
  }

  private func currentDraft() -> EditableNote? {
    guard var draft = note, draft.fields.count == fieldEditors.count else { return nil }
    for index in draft.fields.indices {
      draft.fields[index].value = fieldEditors[index].text
    }
    draft.tags = (tagsField.text ?? "")
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
    return draft
  }

  @objc private func save() {
    guard let draft = currentDraft() else { return }
    setBusy(true)
    provider.saveNote(draft) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.setBusy(false)
        switch result {
        case .success:
          self.note = draft
          self.navigationController?.popViewController(animated: true)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  @objc private func addMedia() {
    let picker = UIDocumentPickerViewController(
      documentTypes: [kUTTypeAudio as String, kUTTypeImage as String, kUTTypeMovie as String],
      in: .import
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker, animated: true)
  }

  @objc private func recordAudio() {
    if recorder.isRecording {
      recordButton.setTitle("录制音频", for: .normal)
      guard let url = recorder.stop() else {
        showAlert("录音未生成")
        return
      }
      storeMedia(
        at: url, suggestedName: "said_note_\(noteID)_\(Int(Date().timeIntervalSince1970)).wav")
      return
    }
    recorder.requestPermission { [weak self] allowed in
      guard let self = self else { return }
      guard allowed else {
        self.showAlert("请在系统设置中允许 Said 使用麦克风")
        return
      }
      do {
        try self.recorder.start()
        self.recordButton.setTitle("停止录音", for: .normal)
      } catch {
        self.showAlert(error.localizedDescription)
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
  {
    guard let url = urls.first else { return }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    storeMedia(at: url, suggestedName: url.lastPathComponent)
  }

  private func storeMedia(at url: URL, suggestedName: String) {
    guard currentDraft() != nil, !fieldEditors.isEmpty else { return }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if (values.fileSize ?? 0) > 50 * 1024 * 1024 {
        showAlert("媒体文件超过 50 MB，不适合当前设备")
        return
      }
    } catch {
      showAlert(error.localizedDescription)
      return
    }
    let fieldIndex = min(max(activeFieldIndex, 0), fieldEditors.count - 1)
    setBusy(true)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      let result: Result<Data, Error>
      do { result = .success(try Data(contentsOf: url, options: .mappedIfSafe)) } catch {
        result = .failure(error)
      }
      DispatchQueue.main.async {
        switch result {
        case .failure(let error):
          self.setBusy(false)
          self.showAlert(error.localizedDescription)
        case .success(let data):
          self.persistMedia(data, suggestedName: suggestedName, fieldIndex: fieldIndex)
        }
      }
    }
  }

  private func persistMedia(_ data: Data, suggestedName: String, fieldIndex: Int) {
    provider.storeMedia(data: data, suggestedName: suggestedName, fieldIndex: fieldIndex) {
      [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.setBusy(false)
        switch result {
        case .success(let insertion):
          guard self.fieldEditors.indices.contains(insertion.fieldIndex) else { return }
          let editor = self.fieldEditors[insertion.fieldIndex]
          if !editor.text.isEmpty, !editor.text.hasSuffix("\n") {
            editor.text.append("\n")
          }
          editor.text.append(insertion.markup)
        case .failure(let error):
          self.showAlert(error.localizedDescription)
        }
      }
    }
  }

  private func setBusy(_ busy: Bool) {
    if busy {
      activityIndicator.startAnimating()
    } else {
      activityIndicator.stopAnimating()
    }
    navigationItem.rightBarButtonItem?.isEnabled = !busy && note != nil
    mediaButton.isEnabled = !busy && note != nil && !fieldEditors.isEmpty
    recordButton.isEnabled = !busy && note != nil && !fieldEditors.isEmpty
  }

  private func showAlert(_ message: String) {
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  private func observeKeyboard() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillChange(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillHide(_:)),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )
  }

  @objc private func keyboardWillChange(_ notification: Notification) {
    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    else { return }
    let covered = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
    scrollView.contentInset.bottom = covered
    scrollView.scrollIndicatorInsets.bottom = covered
  }

  @objc private func keyboardWillHide(_ notification: Notification) {
    scrollView.contentInset.bottom = 0
    scrollView.scrollIndicatorInsets.bottom = 0
  }
}

extension NoteEditorViewController: UITextViewDelegate {
  func textViewDidBeginEditing(_ textView: UITextView) {
    activeFieldIndex = textView.tag
  }
}
