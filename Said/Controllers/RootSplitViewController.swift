import UIKit

/// Said's two-pane shell. At widths below 520 points the sidebar becomes a drawer.
final class RootSplitViewController: UIViewController, ThemeRefreshable, UIGestureRecognizerDelegate {
    private let sidebarViewController = SidebarViewController()
    private let sidebarContainer = UIView()
    private let drawerCloseHandle = UIView()
    private let divider = UIView()
    private let contentContainer = UIView()
    private let dimView = UIView()

    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var sidebarLeadingConstraint: NSLayoutConstraint!
    private var contentLeadingWideConstraint: NSLayoutConstraint!
    private var contentLeadingCompactConstraint: NSLayoutConstraint!
    private var dividerWidthConstraint: NSLayoutConstraint!
    private var drawerPanGesture: UIPanGestureRecognizer!
    private var edgePanGesture: UIScreenEdgePanGestureRecognizer!

    private var navigationControllers: [SaidSection: UINavigationController] = [:]
    private var activeNavigationController: UINavigationController?
    private var selectedSection: SaidSection = .decks
    private var isCompactLayout = false
    private var isDrawerOpen = false
    private var isSidebarCollapsed = true
    private let managementProvider = OfficialBrowserProvider()
    private let syncProvider = OfficialSyncProvider()

    override func viewDidLoad() {
        super.viewDidLoad()
        isSidebarCollapsed = UserDefaults.standard.bool(forKey: "said_sidebar_collapsed")
        sidebarViewController.delegate = self
        buildView()
        showSection(.decks)
        applyTheme()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .saidThemeDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        DSTheme.c.statusBarStyle
    }

    override var childForStatusBarStyle: UIViewController? {
        activeNavigationController
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let compact = view.bounds.width > 0 && view.bounds.width < DSTheme.compactBreakpoint
        if compact != isCompactLayout {
            isCompactLayout = compact
            applyLayoutMode(animated: false)
        }
    }

    func applyTheme() {
        let colors = DSTheme.c
        view.backgroundColor = colors.background
        sidebarContainer.backgroundColor = colors.sidebarBackground
        contentContainer.backgroundColor = colors.background
        divider.backgroundColor = colors.divider

        navigationControllers.values.forEach { styleNavigationController($0) }
        sidebarViewController.applyTheme()
        updateSidebarButton()
        setNeedsStatusBarAppearanceUpdate()

        sidebarContainer.layer.shadowColor = UIColor.black.cgColor
        sidebarContainer.layer.shadowOpacity = isCompactLayout ? 0.28 : 0
        sidebarContainer.layer.shadowRadius = 10
        sidebarContainer.layer.shadowOffset = CGSize(width: 2, height: 0)
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func buildView() {
        [contentContainer, divider, dimView, sidebarContainer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        addChild(sidebarViewController)
        sidebarViewController.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(sidebarViewController.view)
        sidebarViewController.didMove(toParent: self)

        drawerCloseHandle.translatesAutoresizingMaskIntoConstraints = false
        drawerCloseHandle.backgroundColor = .clear
        drawerCloseHandle.isHidden = true
        drawerCloseHandle.accessibilityLabel = "关闭侧栏手势区域"
        sidebarContainer.addSubview(drawerCloseHandle)

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        dimView.alpha = 0
        dimView.isHidden = true
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeDrawer)))

        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(
            equalToConstant: DSTheme.sidebarWidth
        )
        sidebarLeadingConstraint = sidebarContainer.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: isSidebarCollapsed ? -DSTheme.sidebarWidth : 0
        )
        dividerWidthConstraint = divider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        contentLeadingWideConstraint = contentContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor)
        contentLeadingCompactConstraint = contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor)

        NSLayoutConstraint.activate([
            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarLeadingConstraint,
            sidebarWidthConstraint,

            sidebarViewController.view.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarViewController.view.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
            sidebarViewController.view.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarViewController.view.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),

            drawerCloseHandle.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            drawerCloseHandle.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
            drawerCloseHandle.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            drawerCloseHandle.widthAnchor.constraint(equalToConstant: 22),

            divider.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dividerWidthConstraint,

            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentLeadingWideConstraint,

            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        sidebarContainer.clipsToBounds = false

        edgePanGesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handleEdgePan(_:))
        )
        edgePanGesture.edges = .left
        edgePanGesture.delegate = self
        view.addGestureRecognizer(edgePanGesture)

        drawerPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrawerPan(_:)))
        drawerPanGesture.maximumNumberOfTouches = 1
        drawerPanGesture.cancelsTouchesInView = false
        drawerPanGesture.delegate = self
        drawerCloseHandle.addGestureRecognizer(drawerPanGesture)
    }

    private func navigationController(for section: SaidSection) -> UINavigationController {
        if let existing = navigationControllers[section] {
            return existing
        }

        let root: UIViewController
        switch section {
        case .decks:
            root = DeckListViewController()
        case .settings:
            root = SettingsViewController()
        case .browse:
            root = BrowserViewController(provider: managementProvider)
        case .stats:
            root = StatisticsViewController(provider: managementProvider)
        case .sync:
            root = SyncViewController(provider: syncProvider)
        }

        root.navigationItem.leftBarButtonItem = makeSidebarButton()
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.delegate = self
        navigationController.navigationBar.isTranslucent = false
        styleNavigationController(navigationController)
        navigationControllers[section] = navigationController
        return navigationController
    }

    private func showSection(_ section: SaidSection) {
        let next = navigationController(for: section)
        selectedSection = section
        sidebarViewController.select(section)

        guard next !== activeNavigationController else {
            closeDrawer()
            return
        }

        if let current = activeNavigationController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            next.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            next.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        next.didMove(toParent: self)
        activeNavigationController = next
        updateSidebarButton()
        closeDrawer()
    }

    private func styleNavigationController(_ navigationController: UINavigationController) {
        DSNavigationBarStyle.apply(to: navigationController)
    }

    private func makeSidebarButton() -> UIBarButtonItem {
        let button = UIButton(type: .system)
        button.setImage(ActionIconFactory.image(.sidebar, pointSize: 18), for: .normal)
        button.tintColor = DSTheme.c.accent
        button.accessibilityLabel = "切换侧栏"
        button.addTarget(self, action: #selector(toggleSidebar), for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return UIBarButtonItem(customView: button)
    }

    private func updateSidebarButton() {
        guard let navigationController = activeNavigationController else { return }
        navigationController.viewControllers.forEach { installSidebarButton(on: $0, in: navigationController) }
    }

    private func installSidebarButton(on controller: UIViewController, in navigationController: UINavigationController) {
        let open = isCompactLayout ? isDrawerOpen : !isSidebarCollapsed
        let sidebar = ActionIconFactory.barItem(
            kind: open ? .sidebarOpen : .sidebar,
            target: self,
            action: #selector(toggleSidebar),
            accessibility: open ? "Close sidebar" : "Open sidebar"
        )
        controller.navigationItem.leftItemsSupplementBackButton = false
        if controller === navigationController.viewControllers.first {
            controller.navigationItem.leftBarButtonItems = [sidebar]
        } else {
            let back = ActionIconFactory.barItem(
                kind: .back,
                target: self,
                action: #selector(popActiveViewController),
                accessibility: "返回"
            )
            // Sidebar is always the first, leftmost navigation action.
            controller.navigationItem.leftBarButtonItems = [sidebar, back]
        }
    }

    @objc private func popActiveViewController() {
        activeNavigationController?.popViewController(animated: true)
    }

    private func applyLayoutMode(animated: Bool) {
        isDrawerOpen = false
        dimView.alpha = 0
        dimView.isHidden = true

        if isCompactLayout {
            contentLeadingWideConstraint.isActive = false
            contentLeadingCompactConstraint.isActive = true
            sidebarWidthConstraint.constant = DSTheme.sidebarWidth
            sidebarLeadingConstraint.constant = -DSTheme.sidebarWidth
            dividerWidthConstraint.constant = 0
            divider.isHidden = true
        } else {
            contentLeadingCompactConstraint.isActive = false
            contentLeadingWideConstraint.isActive = true
            isSidebarCollapsed = UserDefaults.standard.bool(forKey: "said_sidebar_collapsed")
            sidebarWidthConstraint.constant = DSTheme.sidebarWidth
            sidebarLeadingConstraint.constant = isSidebarCollapsed ? -DSTheme.sidebarWidth : 0
            dividerWidthConstraint.constant =
                isSidebarCollapsed ? 0 : 1 / UIScreen.main.scale
            divider.isHidden = false
        }

        applyTheme()
        updateDrawerCloseHandle()
        updateSidebarButton()
        let updates = { self.view.layoutIfNeeded() }
        animated ? UIView.animate(withDuration: 0.22, animations: updates) : updates()
    }

    @objc private func toggleSidebar() {
        if isCompactLayout {
            isDrawerOpen ? closeDrawer() : openDrawer()
            return
        }

        isSidebarCollapsed.toggle()
        UserDefaults.standard.set(isSidebarCollapsed, forKey: "said_sidebar_collapsed")
        sidebarLeadingConstraint.constant = isSidebarCollapsed ? -DSTheme.sidebarWidth : 0
        dividerWidthConstraint.constant = isSidebarCollapsed ? 0 : 1 / UIScreen.main.scale
        updateSidebarButton()
        UIView.animate(withDuration: 0.22) {
            self.view.layoutIfNeeded()
        }
    }

    private func openDrawer() {
        guard isCompactLayout else { return }
        isDrawerOpen = true
        dimView.isHidden = false
        sidebarLeadingConstraint.constant = 0
        view.bringSubviewToFront(dimView)
        view.bringSubviewToFront(sidebarContainer)
        updateDrawerCloseHandle()
        updateSidebarButton()
        UIView.animate(withDuration: 0.22) {
            self.dimView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    @objc private func closeDrawer() {
        guard isCompactLayout, isDrawerOpen else { return }
        isDrawerOpen = false
        sidebarLeadingConstraint.constant = -DSTheme.sidebarWidth
        updateDrawerCloseHandle()
        updateSidebarButton()
        UIView.animate(withDuration: 0.22, animations: {
            self.dimView.alpha = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if !self.isDrawerOpen {
                self.dimView.isHidden = true
            }
        })
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard isCompactLayout else { return }
        let translation = gesture.translation(in: view).x
        switch gesture.state {
        case .began:
            dimView.isHidden = false
            view.bringSubviewToFront(dimView)
            view.bringSubviewToFront(sidebarContainer)
        case .changed:
            let position = min(0, max(-DSTheme.sidebarWidth, -DSTheme.sidebarWidth + translation))
            sidebarLeadingConstraint.constant = position
            dimView.alpha = (position + DSTheme.sidebarWidth) / DSTheme.sidebarWidth
            view.layoutIfNeeded()
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            if sidebarLeadingConstraint.constant > -DSTheme.sidebarWidth * 0.45 || velocity > 500 {
                openDrawer()
            } else {
                isDrawerOpen = true
                closeDrawer()
            }
        default:
            break
        }
    }

    @objc private func handleDrawerPan(_ gesture: UIPanGestureRecognizer) {
        guard isCompactLayout, isDrawerOpen else { return }
        let translation = gesture.translation(in: view).x
        switch gesture.state {
        case .changed:
            let position = min(0, max(-DSTheme.sidebarWidth, translation))
            sidebarLeadingConstraint.constant = position
            dimView.alpha = (position + DSTheme.sidebarWidth) / DSTheme.sidebarWidth
            view.layoutIfNeeded()
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            if sidebarLeadingConstraint.constant < -DSTheme.sidebarWidth * 0.35 || velocity < -400 {
                closeDrawer()
            } else {
                openDrawer()
            }
        default:
            break
        }
    }

    private func updateDrawerCloseHandle() {
        drawerCloseHandle.isHidden = !isCompactLayout || !isDrawerOpen
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isCompactLayout else { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
        if pan === drawerPanGesture {
            return isDrawerOpen && velocity.x < 0
        }
        if pan === edgePanGesture {
            return !isDrawerOpen && velocity.x > 0
        }
        return true
    }
}

extension RootSplitViewController: SidebarViewControllerDelegate {
    func sidebar(_ sidebar: SidebarViewController, didSelect section: SaidSection) {
        showSection(section)
    }
}

extension RootSplitViewController: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        installSidebarButton(on: viewController, in: navigationController)
    }
}
