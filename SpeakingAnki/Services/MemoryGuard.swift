import Foundation
import UIKit

/// Light-touch memory hygiene for 1 GB devices (iPad Air 1).
enum MemoryGuard {
    static func purgeTemporaryAudio(url: URL?) {
        guard let url = url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func trimWebViewProcessIfNeeded() {
        // Best-effort: encourage URL cache cleanup between cards
        URLCache.shared.removeAllCachedResponses()
    }

    static func lowMemoryWarningInstall(on vc: UIViewController, handler: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }
}
