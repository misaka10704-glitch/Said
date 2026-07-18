import UIKit

final class StatisticsViewController: UIViewController, ThemeRefreshable {
  private let provider: StatisticsDataProviding
  private let periodControl = UISegmentedControl(items: ["7 天", "30 天", "1 年"])
  private let deckButton = UIButton(type: .system)
  private let filterStack = UIStackView()
  private let scrollView = UIScrollView()
  private let contentStack = UIStackView()
  private let summaryStack = UIStackView()
  private let factsStack = UIStackView()
  private let chartsStack = UIStackView()
  private let activityIndicator = DSTheme.makeActivityIndicator()
  private let statusLabel = UILabel()
  private var chartTitleLabels: [UILabel] = []
  private var deckChoices: [StatisticsDeckChoice] = []
  private var selectedDeckID: Int64?
  private var requestGeneration = 0

  init(provider: StatisticsDataProviding) {
    self.provider = provider
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "统计"
    configureViews()
    applyTheme()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .saidThemeDidChange,
      object: nil
    )
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshDecksAndStatistics()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureViews() {
    periodControl.selectedSegmentIndex = StatisticsPeriod.week.rawValue
    periodControl.addTarget(self, action: #selector(periodChanged), for: .valueChanged)
    deckButton.setTitle("全部牌组 ▾", for: .normal)
    deckButton.titleLabel?.font = DSTheme.bodyFont(size: 15)
    deckButton.addTarget(self, action: #selector(chooseDeck), for: .touchUpInside)

    filterStack.axis = .vertical
    filterStack.spacing = 8
    filterStack.alignment = .fill
    filterStack.translatesAutoresizingMaskIntoConstraints = false
    filterStack.addArrangedSubview(periodControl)
    filterStack.addArrangedSubview(deckButton)

    scrollView.alwaysBounceVertical = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.spacing = 18
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    summaryStack.axis = .vertical
    summaryStack.spacing = 10
    factsStack.axis = .vertical
    factsStack.spacing = 8
    chartsStack.axis = .vertical
    chartsStack.spacing = 16

    statusLabel.font = DSTheme.bodyFont(size: 15)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    activityIndicator.hidesWhenStopped = true

    contentStack.addArrangedSubview(summaryStack)
    contentStack.addArrangedSubview(factsStack)
    contentStack.addArrangedSubview(activityIndicator)
    contentStack.addArrangedSubview(statusLabel)
    contentStack.addArrangedSubview(chartsStack)
    view.addSubview(filterStack)
    view.addSubview(scrollView)
    scrollView.addSubview(contentStack)

    NSLayoutConstraint.activate([
      filterStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      filterStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: view.leadingAnchor, constant: DSTheme.contentPadding),
      filterStack.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor, constant: -DSTheme.contentPadding),
      filterStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      filterStack.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      filterStack.widthAnchor.constraint(
        equalTo: view.widthAnchor, constant: -DSTheme.contentPadding * 2
      ).withPriority(750),
      periodControl.heightAnchor.constraint(equalToConstant: 32),
      deckButton.heightAnchor.constraint(equalToConstant: 32),
      scrollView.topAnchor.constraint(equalTo: filterStack.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      contentStack.topAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
      contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: scrollView.contentLayoutGuide.leadingAnchor,
        constant: DSTheme.contentPadding),
      contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: scrollView.contentLayoutGuide.trailingAnchor,
        constant: -DSTheme.contentPadding),
      contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
      contentStack.bottomAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DSTheme.contentPadding),
      contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: DSTheme.contentMaxWidth),
      contentStack.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -DSTheme.contentPadding * 2
      ).withPriority(750),
    ])
  }

  func applyTheme() {
    let colors = DSTheme.c
    view.backgroundColor = colors.background
    scrollView.backgroundColor = colors.background
    periodControl.tintColor = colors.accent
    deckButton.tintColor = colors.accent
    statusLabel.textColor = colors.textSecondary
    for label in chartTitleLabels { label.textColor = colors.textPrimary }
    refreshTheme(in: contentStack)
  }

  @objc private func themeDidChange() {
    applyTheme()
  }

  private func refreshTheme(in view: UIView) {
    for subview in view.subviews {
      (subview as? ThemeRefreshable)?.applyTheme()
      refreshTheme(in: subview)
    }
  }

  @objc private func periodChanged() {
    loadStatistics()
  }

  private func refreshDecksAndStatistics() {
    loadStatistics()
    provider.loadStatisticsDecks { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if case .success(let choices) = result {
          self.deckChoices = choices
          if let selectedID = self.selectedDeckID,
             !choices.contains(where: { $0.id == selectedID }) {
            self.selectedDeckID = nil
            self.updateDeckButtonTitle()
            self.loadStatistics()
          }
        }
      }
    }
  }

  @objc private func chooseDeck() {
    var items = [
      SaidMenuItem(
        title: "全部牌组",
        isSelected: selectedDeckID == nil
      ) { [weak self] in self?.selectDeck(nil) }
    ]
    items.append(contentsOf: deckChoices.map { deck in
      SaidMenuItem(
        title: deck.name,
        isSelected: selectedDeckID == deck.id
      ) { [weak self] in self?.selectDeck(deck.id) }
    })
    SaidMenu.present(
      from: self,
      title: "统计范围",
      items: items,
      sourceView: deckButton,
      preferVertical: true
    )
  }

  private func selectDeck(_ deckID: Int64?) {
    guard selectedDeckID != deckID else { return }
    selectedDeckID = deckID
    updateDeckButtonTitle()
    loadStatistics()
  }

  private func updateDeckButtonTitle() {
    let name = selectedDeckID.flatMap { id in
      deckChoices.first(where: { $0.id == id })?.name
    } ?? "全部牌组"
    deckButton.setTitle("\(name) ▾", for: .normal)
  }

  private func loadStatistics() {
    guard let period = StatisticsPeriod(rawValue: periodControl.selectedSegmentIndex) else {
      return
    }
    requestGeneration += 1
    let generation = requestGeneration
    activityIndicator.startAnimating()
    statusLabel.text = nil
    provider.loadStatistics(period: period, deckID: selectedDeckID) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self, generation == self.requestGeneration else { return }
        self.activityIndicator.stopAnimating()
        switch result {
        case .success(let snapshot):
          self.render(snapshot)
        case .failure(let error):
          self.clearContent()
          self.statusLabel.text = error.localizedDescription
        }
      }
    }
  }

  private func clearContent() {
    chartTitleLabels.removeAll()
    for stack in [summaryStack, factsStack, chartsStack] {
      for subview in stack.arrangedSubviews {
        stack.removeArrangedSubview(subview)
        subview.removeFromSuperview()
      }
    }
  }

  private func render(_ snapshot: StatisticsSnapshot) {
    clearContent()
    guard !snapshot.isEmpty else {
      statusLabel.text = "所选牌组在这个范围内暂无统计数据。"
      return
    }
    let values = [
      ("已复习", "\(snapshot.summary.reviewed)"),
      ("学习", "\(snapshot.summary.minutesStudied) 分钟"),
      ("留存率", snapshot.summary.retention.map {
        String(format: "%.1f%%", $0 * 100)
      } ?? "—"),
      ("连续", "\(snapshot.summary.streakDays) 天"),
    ]
    for start in stride(from: 0, to: values.count, by: 2) {
      let row = UIStackView()
      row.axis = .horizontal
      row.spacing = 10
      row.distribution = .fillEqually
      for index in start..<min(start + 2, values.count) {
        let (title, value) = values[index]
        row.addArrangedSubview(StatisticsSummaryCard(title: title, value: value))
      }
      summaryStack.addArrangedSubview(row)
    }
    for fact in snapshot.facts {
      factsStack.addArrangedSubview(StatisticsFactRow(title: fact.title, value: fact.value))
    }
    for chart in snapshot.charts {
      let container = UIStackView()
      container.axis = .vertical
      container.spacing = 8
      let title = UILabel()
      title.text = chart.title
      title.font = DSTheme.titleFont(size: 17)
      title.textColor = DSTheme.c.textPrimary
      chartTitleLabels.append(title)
      let chartView = StatisticsChartView()
      chartView.chart = chart
      chartView.heightAnchor.constraint(equalToConstant: 190).isActive = true
      container.addArrangedSubview(title)
      container.addArrangedSubview(chartView)
      chartsStack.addArrangedSubview(container)
    }
    statusLabel.text = nil
  }
}

private final class StatisticsFactRow: UIView, ThemeRefreshable {
  private let titleLabel = UILabel()
  private let valueLabel = UILabel()

  init(title: String, value: String) {
    super.init(frame: .zero)
    titleLabel.text = title
    titleLabel.font = DSTheme.bodyFont(size: 14)
    valueLabel.text = value
    valueLabel.font = DSTheme.bodyFont(size: 14)
    valueLabel.textAlignment = .right
    valueLabel.numberOfLines = 0
    let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
    stack.axis = .horizontal
    stack.spacing = 12
    stack.alignment = .firstBaseline
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
      valueLabel.widthAnchor.constraint(greaterThanOrEqualTo: widthAnchor, multiplier: 0.45),
    ])
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    backgroundColor = .clear
    titleLabel.textColor = DSTheme.c.textSecondary
    valueLabel.textColor = DSTheme.c.textPrimary
  }
}

private final class StatisticsSummaryCard: UIView, ThemeRefreshable {
  private let valueLabel = UILabel()
  private let titleLabel = UILabel()

  init(title: String, value: String) {
    super.init(frame: .zero)
    valueLabel.text = value
    valueLabel.font = DSTheme.titleFont(size: 20)
    valueLabel.textAlignment = .center
    valueLabel.adjustsFontSizeToFitWidth = true
    valueLabel.minimumScaleFactor = 0.7

    titleLabel.text = title
    titleLabel.font = DSTheme.bodyFont(size: 11)
    titleLabel.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
    stack.axis = .vertical
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 66),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    backgroundColor = .clear
    valueLabel.textColor = DSTheme.c.textPrimary
    titleLabel.textColor = DSTheme.c.textSecondary
  }
}

private final class StatisticsChartView: UIView, ThemeRefreshable {
  var chart: StatisticsChart? {
    didSet { setNeedsDisplay() }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyTheme() {
    backgroundColor = .clear
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    DSTheme.c.background.setFill()
    context.fill(rect)

    let plot = rect.inset(by: UIEdgeInsets(top: 20, left: 42, bottom: 34, right: 16))
    drawGrid(in: plot, context: context)
    guard let chart = chart, !chart.points.isEmpty else {
      drawEmptyMessage(in: rect)
      return
    }
    let maximum = max(chart.points.map { $0.value }.max() ?? 0, 1)
    switch chart.style {
    case .bars:
      drawBars(chart.points, maximum: maximum, in: plot, context: context)
    case .line:
      drawLine(chart.points, maximum: maximum, in: plot, context: context)
    }
    drawLabels(chart.points, in: plot)
  }

  private func drawGrid(in plot: CGRect, context: CGContext) {
    context.saveGState()
    context.setStrokeColor(DSTheme.c.divider.cgColor)
    context.setLineWidth(1)
    for index in 0...4 {
      let y = plot.minY + plot.height * CGFloat(index) / 4
      context.move(to: CGPoint(x: plot.minX, y: y))
      context.addLine(to: CGPoint(x: plot.maxX, y: y))
    }
    context.strokePath()
    context.restoreGState()
  }

  private func drawBars(
    _ points: [StatisticsPoint], maximum: Double, in plot: CGRect, context: CGContext
  ) {
    let slot = plot.width / CGFloat(points.count)
    let width = min(24, slot * 0.58)
    context.setFillColor(DSTheme.c.accent.cgColor)
    for (index, point) in points.enumerated() {
      let height = plot.height * CGFloat(point.value / maximum)
      let x = plot.minX + slot * CGFloat(index) + (slot - width) / 2
      context.fill(CGRect(x: x, y: plot.maxY - height, width: width, height: height))
    }
  }

  private func drawLine(
    _ points: [StatisticsPoint], maximum: Double, in plot: CGRect, context: CGContext
  ) {
    context.saveGState()
    context.setStrokeColor(DSTheme.c.accent.cgColor)
    context.setFillColor(DSTheme.c.accent.cgColor)
    context.setLineWidth(2.5)
    let denominator = CGFloat(max(points.count - 1, 1))
    for (index, point) in points.enumerated() {
      let x = plot.minX + plot.width * CGFloat(index) / denominator
      let y = plot.maxY - plot.height * CGFloat(point.value / maximum)
      if index == 0 {
        context.move(to: CGPoint(x: x, y: y))
      } else {
        context.addLine(to: CGPoint(x: x, y: y))
      }
    }
    context.strokePath()
    for (index, point) in points.enumerated() {
      let x = plot.minX + plot.width * CGFloat(index) / denominator
      let y = plot.maxY - plot.height * CGFloat(point.value / maximum)
      context.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
    }
    context.restoreGState()
  }

  private func drawLabels(_ points: [StatisticsPoint], in plot: CGRect) {
    let visibleIndexes = labelIndexes(count: points.count)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: DSTheme.bodyFont(size: 10),
      .foregroundColor: DSTheme.c.textTertiary,
    ]
    for index in visibleIndexes {
      let denominator = CGFloat(max(points.count - 1, 1))
      let centerX = plot.minX + plot.width * CGFloat(index) / denominator
      let string = points[index].label as NSString
      let size = string.size(withAttributes: attributes)
      string.draw(
        at: CGPoint(x: centerX - size.width / 2, y: plot.maxY + 8),
        withAttributes: attributes
      )
    }
  }

  private func labelIndexes(count: Int) -> [Int] {
    guard count > 5 else { return Array(0..<count) }
    return [0, count / 4, count / 2, count * 3 / 4, count - 1]
  }

  private func drawEmptyMessage(in rect: CGRect) {
    let string = "暂无图表数据" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: DSTheme.bodyFont(size: 14),
      .foregroundColor: DSTheme.c.textSecondary,
    ]
    let size = string.size(withAttributes: attributes)
    string.draw(
      at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
      withAttributes: attributes
    )
  }
}
