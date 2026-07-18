import Foundation
import MobileCoreServices
import UIKit

struct LocalCollectionBackup: Equatable {
  let url: URL
  let createdAt: Date
  let byteCount: Int64
}

struct CollectionRestoreConfirmation {
  let id: UUID
  let sourceURL: URL
  let displayName: String
  let warning: String
  let requiredText: String
}

enum CollectionExportKind {
  case apkg(options: SaidApkgExportOptions, filePrefix: String)
  case colpkg(includeMedia: Bool)
  case noteCSV
  case cardCSV
}

enum CollectionImportResult {
  case apkg(SaidApkgImportResult)
  case text(String)
}

protocol LocalDataMaintenanceProviding: AnyObject {
  func listBackups(completion: @escaping (Result<[LocalCollectionBackup], Error>) -> Void)
  func createBackup(completion: @escaping (Result<Bool, Error>) -> Void)
  func prepareRestore(from url: URL) -> CollectionRestoreConfirmation
  func restore(
    _ confirmation: CollectionRestoreConfirmation, typedText: String,
    completion: @escaping (Result<Void, Error>) -> Void)
  func checkDatabase(completion: @escaping (Result<[String], Error>) -> Void)
  func importFile(at url: URL, completion: @escaping (Result<CollectionImportResult, Error>) -> Void)
  func export(
    _ kind: CollectionExportKind, to url: URL,
    completion: @escaping (Result<UInt32?, Error>) -> Void)
}

private enum DataMaintenanceError: LocalizedError {
  case confirmationMismatch
  case unsupportedFile(String)

  var errorDescription: String? {
    switch self {
    case .confirmationMismatch:
      return "确认文字不匹配，未恢复集合。"
    case .unsupportedFile(let ext):
      return "不支持的导入格式：.\(ext)"
    }
  }
}

final class OfficialLocalDataMaintenanceProvider: LocalDataMaintenanceProviding {
  private let queue = DispatchQueue(label: "com.said.anki.local-data-maintenance")

  func listBackups(completion: @escaping (Result<[LocalCollectionBackup], Error>) -> Void) {
    queue.async {
      do {
        let collection = try AnkiStore.shared.requireCollection()
        let urls = try FileManager.default.contentsOfDirectory(
          at: collection.backupsDir,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
        let backups = try urls.filter {
          $0.pathExtension.lowercased() == "colpkg"
        }.map { url -> LocalCollectionBackup in
          let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
          return LocalCollectionBackup(
            url: url,
            createdAt: (attributes[.modificationDate] as? Date) ?? Date.distantPast,
            byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0
          )
        }.sorted { $0.createdAt > $1.createdAt }
        completion(.success(backups))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func createBackup(completion: @escaping (Result<Bool, Error>) -> Void) {
    queue.async {
      do {
        completion(.success(try AnkiStore.shared.requireCollection().createBackup(force: true)))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func prepareRestore(from url: URL) -> CollectionRestoreConfirmation {
    CollectionRestoreConfirmation(
      id: UUID(),
      sourceURL: url,
      displayName: url.lastPathComponent,
      warning: "恢复会用所选 COLPKG 替换当前集合。现有集合将在恢复前先创建备份。",
      requiredText: "恢复"
    )
  }

  func restore(
    _ confirmation: CollectionRestoreConfirmation,
    typedText: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard typedText == confirmation.requiredText else {
      completion(.failure(DataMaintenanceError.confirmationMismatch))
      return
    }
    queue.async {
      do {
        let collection = try AnkiStore.shared.requireCollection()
        _ = try collection.createBackup(force: true)
        try collection.restoreCollectionPackage(from: confirmation.sourceURL)
        completion(.success(()))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func checkDatabase(completion: @escaping (Result<[String], Error>) -> Void) {
    queue.async {
      do {
        completion(.success(try AnkiStore.shared.requireCollection().checkDatabase()))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func importFile(at url: URL, completion: @escaping (Result<CollectionImportResult, Error>) -> Void) {
    queue.async {
      do {
        let ext = url.pathExtension.lowercased()
        let collection = try AnkiStore.shared.requireCollection()
        switch ext {
        case "apkg":
          let result = try collection.importApkg(from: url)
          completion(.success(.apkg(result)))
        case "csv", "tsv", "txt":
          let summary = try collection.importText(from: url)
          completion(.success(.text("文本导入完成：\(summary)")))
        default:
          completion(.failure(DataMaintenanceError.unsupportedFile(ext)))
        }
      } catch {
        completion(.failure(error))
      }
    }
  }

  func export(
    _ kind: CollectionExportKind,
    to url: URL,
    completion: @escaping (Result<UInt32?, Error>) -> Void
  ) {
    queue.async {
      do {
        let collection = try AnkiStore.shared.requireCollection()
        switch kind {
        case .apkg(let options, _):
          try collection.exportApkg(to: url, options: options)
          completion(.success(nil))
        case .colpkg(let includeMedia):
          try collection.exportCollectionPackage(to: url, includeMedia: includeMedia)
          completion(.success(nil))
        case .noteCSV:
          completion(.success(try collection.exportNotesText(to: url)))
        case .cardCSV:
          completion(.success(try collection.exportCardsText(to: url)))
        }
      } catch {
        completion(.failure(error))
      }
    }
  }
}

final class DataMaintenanceViewController: UITableViewController, UIDocumentPickerDelegate,
  ThemeRefreshable
{
  private let provider: LocalDataMaintenanceProviding
  private var backups: [LocalCollectionBackup] = []
  private var pendingImportedFile: URL?
  private var spinner: UIActivityIndicatorView?

  private let actions = [
    "导出完整备份（含媒体与配置）",
    "从完整备份恢复",
    "立即备份集合",
    "官方数据库检查",
    "导入 APKG / COLPKG / CSV",
    "换机导出 APKG",
    "导出 APKG（含媒体，桌面同步）",
    "导出 COLPKG",
    "导出笔记 CSV",
    "导出卡片 CSV",
  ]

  init(provider: LocalDataMaintenanceProviding = OfficialLocalDataMaintenanceProvider()) {
    self.provider = provider
    super.init(style: .grouped)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "本地数据维护"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MaintenanceCell")
    tableView.rowHeight = DSTheme.List.rowHeight
    tableView.estimatedRowHeight = DSTheme.List.rowHeight
    tableView.cellLayoutMarginsFollowReadableWidth = true
    tableView.layoutMargins = UIEdgeInsets(
      top: 0,
      left: DSTheme.contentPadding,
      bottom: 0,
      right: DSTheme.contentPadding
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
    applyTheme()
    reloadBackups()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    if let url = pendingImportedFile {
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
  }

  func applyTheme() {
    view.backgroundColor = DSTheme.c.background
    tableView.backgroundColor = DSTheme.c.background
    tableView.separatorColor = DSTheme.c.divider
    tableView.tintColor = DSTheme.c.accent
    tableView.reloadData()
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  override func numberOfSections(in tableView: UITableView) -> Int {
    2
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? actions.count : backups.count
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    section == 0 ? "维护与传输" : "集合备份（点按恢复）"
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    guard section == 1 else { return nil }
    return "应用启动时会按 Anki 的备份间隔自动备份；手动备份会立即执行。备份不含媒体。"
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "MaintenanceCell", for: indexPath)
    cell.backgroundColor = DSTheme.c.surface
    cell.textLabel?.textColor = DSTheme.c.textPrimary
    cell.detailTextLabel?.textColor = DSTheme.c.textSecondary
    cell.accessoryType = .disclosureIndicator
    if indexPath.section == 0 {
      cell.textLabel?.text = actions[indexPath.row]
      cell.textLabel?.numberOfLines = 1
    } else {
      let backup = backups[indexPath.row]
      cell.textLabel?.numberOfLines = 2
      cell.textLabel?.text =
        "\(Self.dateFormatter.string(from: backup.createdAt))\n\(ByteCountFormatter.string(fromByteCount: backup.byteCount, countStyle: .file))"
    }
    return cell
  }

  override func tableView(
    _ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int
  ) {
    (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = DSTheme.c.textSecondary
  }

  override func tableView(
    _ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int
  ) {
    (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = DSTheme.c.textTertiary
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if indexPath.section == 1 {
      beginRestore(from: backups[indexPath.row].url)
      return
    }
    switch indexPath.row {
    case 0: exportFullBackup()
    case 1: pickFullBackupImport()
    case 2: createBackup()
    case 3: checkDatabase()
    case 4: pickImportFile()
    case 5:
      export(
        .apkg(options: .deviceMigration(), filePrefix: "Said_migration"),
        fileExtension: "apkg"
      )
    case 6:
      export(
        .apkg(options: .desktopSync(deckID: nil, includeScheduling: true), filePrefix: "Said_sync"),
        fileExtension: "apkg"
      )
    case 7: chooseColpkgExport(sourceView: tableView.cellForRow(at: indexPath))
    case 8: export(.noteCSV, fileExtension: "csv")
    case 9: export(.cardCSV, fileExtension: "csv")
    default: break
    }
  }

  private func reloadBackups() {
    provider.listBackups { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if case .success(let backups) = result {
          self.backups = backups
          self.tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
        }
      }
    }
  }

  private func createBackup() {
    setBusy(true)
    provider.createBackup { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.setBusy(false)
        switch result {
        case .success(let created):
          self.showMessage(created ? "备份已创建" : "集合没有新变化，无需备份")
          self.reloadBackups()
        case .failure(let error):
          self.showMessage(error.localizedDescription)
        }
      }
    }
  }

  private func checkDatabase() {
    setBusy(true)
    provider.checkDatabase { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.setBusy(false)
        switch result {
        case .success(let problems):
          self.showMessage(
            problems.isEmpty
              ? "官方数据库检查完成，未报告问题。"
              : "检查完成：\n" + problems.joined(separator: "\n"))
        case .failure(let error):
          self.showMessage(error.localizedDescription)
        }
      }
    }
  }

  private func pickImportFile() {
    let picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
  {
    guard let source = urls.first else { return }
    let accessing = source.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        source.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("said-import-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let localURL = folder.appendingPathComponent(source.lastPathComponent)
      try FileManager.default.copyItem(at: source, to: localURL)
      pendingImportedFile = localURL
      let ext = localURL.pathExtension.lowercased()
      if ext == "colpkg" {
        beginRestore(from: localURL)
      } else if ext == SaidAppBackupService.fileExtension {
        beginFullBackupRestore(from: localURL)
      } else {
        importFile(localURL)
      }
    } catch {
      showMessage(error.localizedDescription)
    }
  }

  private func importFile(_ url: URL) {
    setBusy(true)
    provider.importFile(at: url) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.setBusy(false)
        self.removePendingImport()
        switch result {
        case .success(let importResult):
          switch importResult {
          case .apkg(let summary):
            self.showMessage(summary.formattedMessage)
          case .text(let message):
            self.showMessage(message)
          }
        case .failure(let error):
          self.showMessage(error.localizedDescription)
        }
      }
    }
  }

  private func beginRestore(from url: URL) {
    let confirmation = provider.prepareRestore(from: url)
    let first = UIAlertController(
      title: "恢复 \(confirmation.displayName)？",
      message: confirmation.warning,
      preferredStyle: .alert
    )
    first.addAction(
      UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
        self?.removePendingImport()
      })
    first.addAction(
      UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
        self?.showSecondRestoreConfirmation(confirmation)
      })
    present(first, animated: true)
  }

  private func showSecondRestoreConfirmation(_ confirmation: CollectionRestoreConfirmation) {
    let second = UIAlertController(
      title: "二次确认",
      message: "请输入“\(confirmation.requiredText)”以确认替换当前集合。",
      preferredStyle: .alert
    )
    second.addTextField { $0.autocorrectionType = .no }
    second.addAction(
      UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
        self?.removePendingImport()
      })
    second.addAction(
      UIAlertAction(title: "恢复集合", style: .destructive) { [weak self] _ in
        guard let self = self else { return }
        self.setBusy(true)
        self.provider.restore(
          confirmation,
          typedText: second.textFields?.first?.text ?? ""
        ) { result in
          DispatchQueue.main.async {
            self.setBusy(false)
            self.removePendingImport()
            switch result {
            case .success:
              self.showMessage("集合恢复完成")
              self.reloadBackups()
            case .failure(let error):
              self.showMessage(error.localizedDescription)
            }
          }
        }
      })
    present(second, animated: true)
  }

  private func pickFullBackupImport() {
    let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.archive"], in: .import)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker, animated: true)
  }

  private func exportFullBackup() {
    do {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("said-full-backup-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let stamp = Self.backupStampFormatter.string(from: Date())
      let url = folder.appendingPathComponent("SaidBackup_\(stamp).\(SaidAppBackupService.fileExtension)")
      setBusy(true)
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        do {
          _ = try SaidAppBackupService.export(to: url)
          DispatchQueue.main.async {
            guard let self = self else { return }
            self.setBusy(false)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
              try? FileManager.default.removeItem(at: folder)
            }
            if let popover = activity.popoverPresentationController {
              popover.sourceView = self.view
              popover.sourceRect = CGRect(
                x: self.view.bounds.midX,
                y: self.view.bounds.midY,
                width: 1,
                height: 1
              )
            }
            self.present(activity, animated: true)
          }
        } catch {
          DispatchQueue.main.async {
            guard let self = self else { return }
            self.setBusy(false)
            try? FileManager.default.removeItem(at: folder)
            self.showMessage(error.localizedDescription)
          }
        }
      }
    } catch {
      showMessage(error.localizedDescription)
    }
  }

  private func beginFullBackupRestore(from url: URL) {
    let alert = UIAlertController(
      title: "从完整备份恢复？",
      message: "将替换当前集合、偏好设置、钥匙串密钥、Edge TTS 参考音频与发音练习录音。此操作不可撤销。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
      self?.removePendingImport()
    })
    alert.addAction(UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
      self?.confirmFullBackupRestore(from: url)
    })
    present(alert, animated: true)
  }

  private func confirmFullBackupRestore(from url: URL) {
    let alert = UIAlertController(
      title: "二次确认",
      message: "请输入“恢复完整备份”以确认。",
      preferredStyle: .alert
    )
    alert.addTextField { $0.autocorrectionType = .no }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
      self?.removePendingImport()
    })
    alert.addAction(UIAlertAction(title: "恢复", style: .destructive) { [weak self] _ in
      guard let self = self else { return }
      guard alert.textFields?.first?.text == "恢复完整备份" else {
        self.removePendingImport()
        self.showMessage("确认文字不匹配，未恢复。")
        return
      }
      self.setBusy(true)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          _ = try SaidAppBackupService.importBackup(from: url)
          DispatchQueue.main.async {
            self.setBusy(false)
            self.removePendingImport()
            self.showMessage("完整备份已恢复。建议返回牌组列表确认数据。")
            self.reloadBackups()
          }
        } catch {
          DispatchQueue.main.async {
            self.setBusy(false)
            self.removePendingImport()
            self.showMessage(error.localizedDescription)
          }
        }
      }
    })
    present(alert, animated: true)
  }

  private func chooseColpkgExport(sourceView: UIView?) {
    SaidMenu.present(
      from: self,
      title: "导出 COLPKG",
      items: [
        SaidMenuItem(title: "包含媒体", icon: .sync) { [weak self] in
          self?.export(.colpkg(includeMedia: true), fileExtension: "colpkg")
        },
        SaidMenuItem(title: "仅集合", icon: .sync) { [weak self] in
          self?.export(.colpkg(includeMedia: false), fileExtension: "colpkg")
        },
      ],
      sourceView: sourceView ?? view,
      sourceRect: sourceView?.bounds,
      preferVertical: true
    )
  }

  private func export(_ kind: CollectionExportKind, fileExtension ext: String) {
    do {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("said-export-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let stamp = Int(Date().timeIntervalSince1970)
      let prefix: String
      switch kind {
      case .apkg(_, let filePrefix): prefix = filePrefix
      case .colpkg: prefix = "Said_collection"
      case .noteCSV: prefix = "Said_notes"
      case .cardCSV: prefix = "Said_cards"
      }
      let url = folder.appendingPathComponent("\(prefix)_\(stamp).\(ext)")
      setBusy(true)
      provider.export(kind, to: url) { [weak self] result in
        DispatchQueue.main.async {
          guard let self = self else { return }
          self.setBusy(false)
          switch result {
          case .success:
            let activity = UIActivityViewController(
              activityItems: [url],
              applicationActivities: nil
            )
            activity.completionWithItemsHandler = { _, _, _, _ in
              try? FileManager.default.removeItem(at: folder)
            }
            if let popover = activity.popoverPresentationController {
              popover.sourceView = self.view
              popover.sourceRect = CGRect(
                x: self.view.bounds.midX,
                y: self.view.bounds.midY,
                width: 1,
                height: 1
              )
            }
            self.present(activity, animated: true)
          case .failure(let error):
            try? FileManager.default.removeItem(at: folder)
            self.showMessage(error.localizedDescription)
          }
        }
      }
    } catch {
      showMessage(error.localizedDescription)
    }
  }

  private func setBusy(_ busy: Bool) {
    tableView.isUserInteractionEnabled = !busy
    if busy {
      let indicator = UIActivityIndicatorView(style: .gray)
      indicator.startAnimating()
      spinner = indicator
      navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
    } else {
      spinner = nil
      navigationItem.rightBarButtonItem = nil
    }
  }

  private func removePendingImport() {
    guard let url = pendingImportedFile else { return }
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    pendingImportedFile = nil
  }

  private func showMessage(_ message: String) {
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  private static let backupStampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return formatter
  }()
}
