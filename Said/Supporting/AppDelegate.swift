import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UserDefaults.standard.register(defaults: ["said_sidebar_collapsed": true])
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootSplitViewController()
        window.backgroundColor = DSTheme.c.background
        window.makeKeyAndVisible()
        self.window = window

        AnkiStore.shared.bootstrapIfNeeded()
        return true
    }
}
